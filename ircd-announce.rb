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
		rd, wr = IO.select(fds, nil, nil, 2)

		rd.each { |fd|
			if fd == @sock
				if nfd = @sock.accept
					@clients << Client.new(nfd)
				end
			else
				if c = @clients[fd]
					handle_client(c)
				end
			end
		}
	rescue
		puts $!, $!.backtrace
		sleep 1
	end

	def main_loop
		start if not @sock
		loop { main_loop_iter }
	end

	def handle_client(c)
		l = gets(c.fd)
		if !l
			c.fd.close rescue nil
			@clients.delete c.fd
		elsif !c.user or !c.nick
			case l.split[0].downcase
			when 'user'
				c.user = true
				welcome_client(c) if c.nick
			when 'nick'
				c.nick = l.split[1]
				welcome_client(c) if c.user
			when 'pass'
			else
				c.fd.close rescue nil
				@clients.delete c.fd
				c = nil
			end
		else
			c.fd.write ":oper!oper@#{IRCD_NAME} PRIVMSG #{c.nick} :#{@message}\r\n"
		end
	end

	def welcome_client(c)
		c.fd.write <<EOS
:#{IRCD_NAME} 001 #{c.nick} :Welcome to the IRC Network #{c.nick}!nope@nope\r
:#{IRCD_NAME} 002 #{c.nick} :Your host is #{IRCD_NAME}, running version ircd-announce 1.0\r
:#{IRCD_NAME} 003 #{c.nick} :This server was created 2000-01-01 00:00:00 +0000\r
:#{IRCD_NAME} 004 #{c.nick} #{IRCD_NAME} bla o o\r
:#{IRCD_NAME} 005 #{c.nick} NETWORK=internet\r
:#{IRCD_NAME} 375 #{c.nick} :- #{IRCD_NAME} message of the day\r
:#{IRCD_NAME} 372 #{c.nick} :- #{@message}\r
:#{IRCD_NAME} 376 #{c.nick} :End of /MOTD command\r
EOS
	end

	def gets(fd)
		l = ''
		while IO.select([fd], nil, nil, 0)
			c = fd.read(1)
			return if !c or c == ''
			l << c
			break if c == "\n"
		end
		l
	end

	class Client
		attr_accessor :nick, :user, :fd
		def initialize(fd)
			@fd = fd
		end
	end
end

if $0 == __FILE__
	msg = ARGV.shift
	abort 'usage: ruby ircd.rb "<message>"' if not ARGV.empty? or msg[0] == ?-

	IrcdAnnounce.new(msg).main_loop
end
