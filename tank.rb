#!/usr/bin/env

require 'net/http'
require 'json'

module Utils
  def self.infer_orientation(last_position, position, distance)
    if last_position.first + distance == position.first && last_position.last == position.last
      'E'
    elsif last_position.first == position.first && last_position.last + distance == position.last
      'S'
    elsif last_position.first - distance == position.first && last_position.last == position.last
      'W'
    elsif last_position.first == position.first && last_position.last - distance == position.last
      'N'
    else
      nil
    end
  end

  def self.project_move(position, orientation, distance)
    case orientation
    when 'N'
      [position.first, position.last - distance]
    when 'E'
      [position.first + distance, position.last]
    when 'S'
      [position.first, position.last + distance]
    when 'W'
      [position.first - distance, position.last]
    end
  end
end

class Laser
  attr_reader :orientation, :position

  SPEED = 2

  def initialize(position)
    @position = position
  end

  def matches?(position)
    if !orientation
      if (@orientation = Utils.infer_orientation(@position, position, SPEED))
      else
        return false
      end
    elsif (position == Utils.project_move(@position, orientation, SPEED))
      return false
    end
    @position = position
    true
  end
end

class Tank
  attr_reader :last_orientation, :position, :orientation_current

  SPEED = 1

  def update(position)
    orientation = Utils.infer_orientation(@position, position, SPEED)
    @last_orientation = orientation || @last_orientation
    @orientation_current = !!orientation
    @position = position
  end
end

class Game
  attr_reader :state

  def initialize(host, id, me)
    @host, @id = host, id
    @http = Net::HTTP.new(host)
    join(me)
    @lasers = []
    @batteries = []
    @opponent = Tank.new
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
    @board = @state['grid'].split("\n")
    @prior_lasers = @lasers
    @lasers = []
    @batteries = []
    @board.each_with_index do |row, y|
      @board.chars.each_with_index do |c, x|
        pos = [x, y]
        case c
        when 'X'
          @me = pos
        when 'O'
          @opponent.update(pos)
        when 'L'
          if (laser = @lasers.find { |l| l.matches?(pos) } )
            @lasers << laser
          else
            @lasers << Laser.new(pos)
          end
        when 'B'
          @batteries << pos
        end
      end
    end
  end

  def running?
    @state['status'] == 'running'
  end

  def make_move(action)
    puts action
    req = Net::HTTP::Post.new(@host.merge("/game/#{@id}/#{action}"))
    req['X-Sm-Playerid'] = @player_id
    res = @http.request(req)
    parse_game(res.body)
  end

  def move
    make_move('noop')
  end
end

game = Game.new(ARGV[0], ARGV[1], ARGV[2])
while (game.running?)
  game.move
end
puts game.state['status']
