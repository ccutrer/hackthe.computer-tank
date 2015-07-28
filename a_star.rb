require 'set'
require_relative 'priority_queue'

class AStar
  def initialize(neighbor_nodes, dist_between, heuristic_cost_estimate, equality = nil)
    @neighbor_nodes = neighbor_nodes
    @dist_between = dist_between
    @heuristic_cost_estimate = heuristic_cost_estimate
    @equality = equality || :==.to_proc
  end

  def find_path(start, goal)
    closedset = Set.new
    openset = Containers::PriorityQueue.new
    openset.push(start, -1)
    came_from = {}
    g_score = Hash.new(Float::INFINITY)
    g_score[start] = 0

    while !openset.empty?
      current = openset.pop

      if (@equality.call(current, goal))
        return reconstruct_path(came_from, current)
      end

      closedset << current
      neighbors = @neighbor_nodes.call(current, goal)
      neighbors.each do |neighbor|
        next if closedset.include?(neighbor)
        tentative_g_score = g_score[current] + @dist_between.call(current, neighbor)

        if tentative_g_score < g_score[neighbor]
          came_from[neighbor] = current
          g_score[neighbor] = tentative_g_score
          priority = g_score[neighbor] + @heuristic_cost_estimate.call(neighbor, goal)
          openset.push(neighbor, -priority)
        end
      end
    end
    return nil
  end

  def reconstruct_path(came_from, current)
    total_path = [current]
    while came_from.include?(current)
      current = came_from[current]
      total_path.unshift(current)
    end
    total_path
  end
end