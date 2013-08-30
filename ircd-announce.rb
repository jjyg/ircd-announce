#!/usr/bin/ruby

require 'socket'

class IrcdAnnounce
	IRCD_HOST = '0.0.0.0'
	IRCD_PORT = $DEBUG ? 6660 : 6667
	IRCD_NAME = 'ircd.announce'

	attr_accessor :message, :clients, :sock
	def initialize(message)
		@message = message
		# fd -> Client
		@clients = {}
		@sock = nil
	end

	def start
		@sock = TCPServer.open(IRCD_HOST, IRCD_PORT)
		if !$VERBOSE
			if pid = Process.fork
				puts "Running in background, pid #{pid}"
				exit!
			end
			$stdin.close
			$stdout.close
			$stderr.close
		end
	end

	def stop
		@sock.close
		@sock = nil

		@clients.each_key { |fd|
			fd.shutdown rescue nil
			fd.close rescue nil
		}
		@clients.clear
	end

	def main_loop_iter
		fds = [@sock] + @clients.keys
		return idle_check if not ret = IO.select(fds, nil, nil, 10)

		ret[0].each { |fd|
			if fd == @sock
				if nfd = @sock.accept
					close_client(@clients.values.first) if @clients.length > 100
					@clients[nfd] = Client.new(nfd)
				end
			else
				if c = @clients[fd]
					handle_client(c)
				end
			end
		}
	rescue
		puts $!, $!.backtrace if $VERBOSE
		sleep 0.1
	end

	def main_loop
		start if not @sock
		loop { main_loop_iter }
	end

	def handle_client(c)
		l = gets(c.fd)
		if !l
			close_client(c)
		elsif l.split[0].downcase == 'quit'
			close_client(c)
		elsif !c.user or !c.nick
			case l.split[0].downcase
			when 'user'
				c.user = l
				welcome_client(c) if c.nick
			when 'nick'
				c.nick = l.split[1]
				welcome_client(c) if c.user
			when 'pass'
			else
				close_client(c)
			end
		else
			c.fd.write ":oper!oper@#{IRCD_NAME} PRIVMSG #{c.nick} :#{@message}\r\n"
		end
	end

	def welcome_client(c)
		c.fd.write <<EOS.gsub("\r", "").gsub("\n", "\r\n")
:#{IRCD_NAME} 001 #{c.nick} :Welcome to the IRC Network #{c.nick}!nope@nope
:#{IRCD_NAME} 002 #{c.nick} :Your host is #{IRCD_NAME}, running version ircd-announce 1.0
:#{IRCD_NAME} 003 #{c.nick} :This server was created 2000-01-01 00:00:00 +0000
:#{IRCD_NAME} 004 #{c.nick} #{IRCD_NAME} bla o o
:#{IRCD_NAME} 005 #{c.nick} NETWORK=internet
:#{IRCD_NAME} 255 #{c.nick} :I have #{@clients.length} clients
:#{IRCD_NAME} 375 #{c.nick} :- #{IRCD_NAME} message of the day
:#{IRCD_NAME} 372 #{c.nick} :- #{@message}
:#{IRCD_NAME} 376 #{c.nick} :End of /MOTD command
:oper!oper@#{IRCD_NAME} PRIVMSG #{c.nick} :#{@message}
EOS

		puts Time.now.strftime("%Y-%m-%d %H:%M:%S ") + "new client #{c.nick.inspect} #{c.hostname.inspect}" if $VERBOSE
	end

	def close_client(c)
		puts Time.now.strftime("%Y-%m-%d %H:%M:%S ") + "close client #{c.nick.inspect} #{c.hostname.inspect}" if $VERBOSE and c.nick and c.user
		c.fd.close rescue nil
		@clients.delete c.fd
	end

	def idle_check
		c = @clients.values.first
		close_client(c) if c and c.creation_time < Time.now - 3600
	end

	def gets(fd)
		l = ''
		while IO.select([fd], nil, nil, 0)
			c = fd.read(1)
			return if !c or c == ''
			l << c
			break if c == "\n"
		end
		l.chomp
	rescue
	end

	class Client
		attr_accessor :nick, :user, :hostname, :fd, :creation_time
		def initialize(fd)
			@fd = fd
			@creation_time = Time.now
			@hostname = @fd.peeraddr[3]
		end
	end
end

if $0 == __FILE__
	msg = ARGV.shift
	abort 'usage: ruby ircd.rb "<message>"' if not msg or not ARGV.empty? or msg[0] == ?-

	IrcdAnnounce.new(msg).main_loop
end
