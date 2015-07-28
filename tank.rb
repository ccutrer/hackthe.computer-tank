#!/usr/bin/env ruby

require 'net/http'
require 'json'
require 'byebug'
require 'uri'

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
    attr_accessor :ttl
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
      Laser.ttl = @state['config']['laser_distance'].to_i
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

  def move
    action = nil
    @lasers.each do |l|
       perpendicular = Utils.perpendicular?(@me.orientation, l.orientation)
       count = perpendicular ? 1 : 2
       moves = l.project_moves(count)
       moves.each do |pos|
         # it will hit a wall, don't worry about it
         break if @board[pos.last][pos.first] == 'W'
         if pos == @me.position
           if perpendicular
             action = 'move'
           else
             action = 'right'
           end
           break
         end
       end
    end

    if @moves == 1
      action = 'fire'
    end
    action ||= 'noop'
    make_move(action)
  end
end

game = Game.new(ARGV[0], ARGV[1], ARGV[2])
while game.running?
  game.move
end
puts game.state['status']
