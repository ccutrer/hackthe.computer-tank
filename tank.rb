#!/usr/bin/env ruby

require 'net/http'
require 'json'
require 'byebug'
require 'uri'
require_relative('a_star')

module Utils
  class << self
    attr_accessor :width, :height

    def infer_orientation(last_position, position, distance)
      if wrap_x(last_position.first + distance) == position.first && last_position.last == position.last
        'E'
      elsif last_position.first == position.first && wrap_y(last_position.last + distance) == position.last
        'S'
      elsif wrap_x(last_position.first - distance) == position.first && last_position.last == position.last
        'W'
      elsif last_position.first == position.first && wrap_y(last_position.last - distance) == position.last
        'N'
      else
        nil
      end
    end
  
    def project_move(position, orientation, distance)
      case orientation
      when 'N'
        [position.first, wrap_y(position.last - distance)]
      when 'E'
        [wrap_x(position.first + distance), position.last]
      when 'S'
        [position.first, wrap_y(position.last + distance)]
      when 'W'
        [wrap_x(position.first - distance), position.last]
      end
    end
  
    def perpendicular?(orientation1, orientation2)
      ((orientation1 == 'N' || orientation1 == 'S') &&
          (orientation2 == 'E' || orientation2 == 'W')) ||
        ((orientation1 == 'E' || orientation1 == 'W') &&
            (orientation2 == 'N' || orientation2 == 'S'))
    end

    def rotate_right(orientation)
      case orientation
        when 'N'
          'E'
        when 'E'
          'S'
        when 'S'
          'W'
        when 'W'
          'N'
      end
    end

    def rotate_left(orientation)
      case orientation
        when 'N'
          'W'
        when 'W'
          'S'
        when 'S'
          'E'
        when 'E'
          'N'
      end
    end

    def wrap_x(x)
      if x < 0
        width + x
      elsif x >= width
        x - width
      else
        x
      end
    end

    def wrap_y(y)
      if y < 0
        height + y
      elsif y >= height
        y - height
      else
        y
      end
    end
  end
end

class Laser
  attr_reader :orientation, :position

  class << self
    attr_accessor :ttl, :energy_required
  end

  SPEED = 2

  def initialize(position, tank1_position, tank1_orientation, tank2_position, tank2_orientation)
    @position = position
    @orientation = tank1_orientation if tank1_orientation && position == Utils.project_move(tank1_position, tank1_orientation, SPEED)
    @orientation ||= tank2_orientation if tank2_orientation && position == Utils.project_move(tank2_position, tank2_orientation, SPEED)
    @orientation ||= Utils.infer_orientation(tank1_position, position, SPEED)
    @orientation ||= Utils.infer_orientation(tank2_position, position, SPEED)
    @ttl = self.class.ttl
  end

  def matches?(position)
    unless (position == Utils.project_move(@position, orientation, SPEED))
      return false
    end
    @position = position
    @ttl -= SPEED
    true
  end

  def project_moves(count)
    moves = []
    return unless orientation
    count.times do
      SPEED.times do
        moves << Utils.project_move(moves.last || @position, orientation, 1)
      end
    end
    # don't forget it might fizzle out first
    moves[0...@ttl]
  end
end

class Tank
  attr_accessor :orientation, :position, :inferred_orientation

  SPEED = 1

  def update(position)
    @orientation = Utils.infer_orientation(@position, position, SPEED) if @position
    @inferred_orientation = @orientation || @inferred_orientation
    @position = position
  end

  def project_move(with_rotation = nil)
    direction = with_rotation ? Utils.send("rotate_#{with_rotation}", orientation) : orientation
    Utils.project_move(position, direction, SPEED)
  end
end

class Game
  attr_reader :state

  def initialize(host, id, me)
    @host, @id = URI.parse(host), id
    @http = Net::HTTP.new(@host.host, @host.port)
    @lasers = []
    @batteries = []
    @opponent = Tank.new
    @me = Tank.new
    @moves = 0
    adjacency = ->(location) do
      [
          [Utils.wrap_x(location.first - 1), location.last],
          [location.first, Utils.wrap_y(location.last - 1)],
          [Utils.wrap_x(location.first + 1), location.last],
          [location.first, Utils.wrap_y(location.last + 1)]
      ].select do |new_location|
        spot(new_location) != 'W'
      end
    end

    cost_func = ->(a, b) { 1 }
    distance_func = ->(location, finish) do
      (finish.last - location.last).abs + (finish.first - location.first).abs
    end
    @a_star = AStar.new(adjacency, cost_func, distance_func)
    join(me)
  end

  def join(me)
    req = Net::HTTP::Post.new(@host.merge("/game/#{@id}/join"))
    req['X-Sm-Playermoniker'] = me
    res = @http.request(req)
    @player_id = res['X-Sm-Playerid']
    parse_game(res.body)
  end

  def parse_game(body)
    @state = JSON.parse(body)
    if @state['config']
      @config = @state['config']
      Laser.ttl = @state['config']['laser_distance']
      Laser.energy_required = @state['config']['laser_energy']
    end

    @board = @state['grid'].split("\n")
    @prior_lasers = @lasers
    @lasers = []
    @batteries = []
    @me.orientation = @state['orientation'][0].upcase
    @opponent_last_spot = @opponent.position
    @opponent_last_orientation = @opponent.orientation
    @my_last_spot = @me.position
    @my_last_orientation = @me.orientation
    Utils.height = @board.length
    Utils.width = @board.first.length
    @board.each_with_index do |row, y|
      row.each_char.each_with_index do |c, x|
        pos = [x, y]
        case c
        when 'X'
          @me.position = pos
        when 'O'
          @opponent.update(pos)
        when 'L'
          if (laser = @prior_lasers.find { |l| l.matches?(pos) } )
            @lasers << laser
          else
            @lasers << Laser.new(pos, @opponent_last_spot, @opponent_last_orientation, @my_last_spot, @my_last_orientation)
          end
        when 'B'
          @batteries << pos
        end
      end
    end
    puts @board
    puts @me.inspect
    puts @opponent.inspect
    puts @lasers.inspect
    puts @batteries.inspect
  end

  def running?
    @state['status'] == 'running'
  end

  def make_move(action)
    puts action
    puts "=" * 40
    req = Net::HTTP::Post.new(@host.merge("/game/#{@id}/#{action}"))
    req['X-Sm-Playerid'] = @player_id
    res = @http.request(req)
    @moves += 1
    parse_game(res.body)
  end

  def spot(pos)
    @board[pos.last][pos.first]
  end

  def avoid_laser
    action = nil
    @lasers.each do |l|
      perpendicular = Utils.perpendicular?(@me.orientation, l.orientation)
      if perpendicular
        best_direction = 'move'
        count = 1
        if spot(@me.project_move) == 'W'
          best_direction = 'right'
          count += 1
          if spot(@me.project_move('right')) == 'W'
            best_direction = 'left'
            # I'm in a corner; gotta reverse out
            if spot(@me.project_move('left')) == 'W'
              count += 1
            end
          end
        end
      else
        best_direction = 'right'
        count = 2
        if spot(@me.project_move('right')) == 'W'
          best_direction = 'left'
          if spot(@me.project_move('left')) == 'W'
            count += 1
            best_direction = 'move'
            if spot(@me.project_move) == 'W'
              count += 2
              best_direction = 'right'
            end
          end
        end
      end

      moves = l.project_moves(count)
      moves.each do |pos|
        # it will hit a wall, don't worry about it
        break if spot(pos) == 'W'
        if pos == @me.position
          if perpendicular
            action = 'move'
          else
            action = best_direction
          end
          break
        end
      end
    end

    action
  end

  def kill_opponent
    return nil unless @state['energy'] > Laser.energy_required
    pos = @me.project_move
    return 'fire' if pos == @opponent.position
    (Laser::SPEED - 1).times do
      break if spot(pos) == 'W'
      pos = Utils.project_move(pos, @me.orientation, 1)
      return 'fire' if pos == @opponent.position
    end
    nil
  end

  def head_towards_something(path)
    return nil if path_length(path) * @config['health_loss'] > @state['health']
    direction = Utils.infer_orientation(path[0], path[1], 1)
    if @me.orientation == direction
      'move'
    elsif Utils.rotate_right(@me.orientation) == direction
      'right'
    elsif Utils.rotate_left(@me.orientation) == direction
      'left'
    else
      'right'
    end
  end

  def path_length(path)
    length = 0
    i = 0
    orientation = @me.orientation
    while (i < path.length - 1)
      direction = Utils.infer_orientation(path[i], path[i + 1], 1)
      length += 1
      if orientation == direction
        i += 1
      elsif Utils.rotate_right(orientation) == direction
        orientation = Utils.rotate_right(orientation)
      elsif Utils.rotate_left(orientation) == direction
        orientation = Utils.rotate_left(orientation)
      else
        orientation = Utils.rotate_right(orientation)
      end
    end
    length
  end

  def seek_out_battery
    # don't bother with batteries if it would overflow our energy
    if @state['energy'] > @config['max_energy'] - @config['battery_power']
      # unless we need the health
      unless @state['health'] < @config['max_health'] - @config['battery_health']
        return nil
      end
    end

    preferred_batteries = @batteries.map do |b|
      @a_star.find_path(@me.position, b)
    end.sort_by(&:length)

    if preferred_batteries.length > 1 &&
        @a_star.find_path(@opponent.position, preferred_batteries.first.last).length < preferred_batteries.first.length
      preferred_batteries.shift
    end
    return nil unless preferred_batteries.first

    head_towards_something(preferred_batteries.first)
  end

  def head_towards_opponent
    path = @a_star.find_path(@me.position, @opponent.position)
    head_towards_something(path)
  end

  def shoot_for_fun
    return nil if @last_fun_shot && @moves - @last_fun_shot < 5
    if @state['energy'] >= 2 * Laser.energy_required
      @last_fun_shot = @moves
      return 'fire'
    end
    nil
  end

  def move
    action = avoid_laser rescue nil
    action ||= kill_opponent rescue nil
    action ||= seek_out_battery rescue nil
    action ||= head_towards_opponent rescue nil
    action ||= shoot_for_fun rescue nil

    action ||= 'noop'
    make_move(action)
  end
end

game = Game.new(ARGV[0], ARGV[1], ARGV[2])
while game.running?
  game.move
end
puts game.state['status']
