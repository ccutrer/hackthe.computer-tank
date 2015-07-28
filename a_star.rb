require 'set'
require_relative 'priority_queue'

class AStar
  def initialize(neighbor_nodes, dist_between, heuristic_cost_estimate)
    @neighbor_nodes = neighbor_nodes
    @dist_between = dist_between
    @heuristic_cost_estimate = heuristic_cost_estimate
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

      if (current == goal)
        return reconstruct_path(came_from, goal)
      end

      closedset << current
      @neighbor_nodes.call(current).each do |neighbor|
        next if closedset.include?(neighbor)
        tentative_g_score = g_score[current] + 1

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