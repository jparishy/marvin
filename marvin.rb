require 'slack-rtmapi'
require 'httparty'
require 'json'
require 'wolfram-alpha'
require 'mongo'

UserID = "U03R6GGV6"

Alex = "U03QV278G"

StrikesPerUser = {}
ChastiseList = {}

IsTest = true

MongoDB = Mongo::Connection.new("localhost", 27017).db("marvin")

# minimarvin vs marvin
Token = IsTest ? "xoxb-3886928374-7T35cOBGldmQdBGDseX85WX9" :
				 "xoxb-3856560992-86I15UC0fyV3VJ9IvObLuDMm"


Name = IsTest ? "minimarvin" : "marvin"

WolframAlphaAppID = "6E942L-EJR26PPRRP"

AbsolutAPIKey = "e288ccbff859479cb92f0637eec77c2e"

url = SlackRTM.get_url token: Token
client = SlackRTM::Client.new websocket_url: url

wolframAlphaOptions = { "format" => "plaintext" }
WolframAlphaClient = WolframAlpha::Client.new WolframAlphaAppID, wolframAlphaOptions

Absurdity = "http://i.imgur.com/gBDtj6J.jpg"

Magic8Ball = [
	"It is certain",
	"It is decidedly so",
	"Without a doubt",
	"Yes definitely",
	"You may rely on it",
	"As I see it, yes",
	"Most likely",
	"Outlook good",
	"Yes",
	"Signs point to yes",
	"Reply hazy try again",
	"Ask again later",
	"Better not tell you now",
	"Cannot predict now",
	"Concentrate and ask again",
	"Don't count on it",
	"My reply is no",
	"My sources say no",
	"Outlook not so good",
	"Very doubtful",
]

def answer_question(question)
	response = WolframAlphaClient.query question

	answer = nil
	response.pods.each do |pod|
		if pod.title == "Result"
			answer = pod.subpods[0].plaintext
		end
	end

	return answer
end

def get_gif(term)
	escaped = term.gsub(" ", "+")
	url = "http://api.giphy.com/v1/gifs/search?q=#{escaped}&api_key=dc6zaTOxFJmzC"
	response = HTTParty.get url
	json = JSON.load(response.body)
	data = json["data"]
	if data.length == 0
		return nil
	end

	return data[0]["images"]["original"]["url"]
end

def search_gif(search)
	if search == nil
		return nil
	end

	query = search[:text].downcase

	if query == "kareem" || query == "kcblack"
		return "LOL pass"
	else
		url = get_gif(query)
		if url != nil
			return url
		else
			return "Didn't find anything :tired_face:"
		end
	end
end

def search_drink(user, query)
	search = query.gsub(" ", "-")
	path = "https://addb.absolutdrinks.com/quickSearch/drinks/#{search}/?apiKey=#{AbsolutAPIKey}"
	puts path
	results = JSON.load(HTTParty.get(path).body)["result"]
	if results.length == 0
		return "Hmm, I dunno man? Jameson is always good."
	else
		drink = results.sample
		name = drink["name"]
		taste = drink["tastes"].sample()["text"].downcase
		how_to_make = drink["descriptionPlain"]

		text = "<@#{user}> how about a #{name}? It's #{taste}. Here's how to make one:\n>#{how_to_make}"
		return text
	end
end

def set_custom_response(from_user, text)
	when_trigger = /when (<@)?(?<user>[\w]*|I|anyone)>? say(s)? (?<trigger>[\S]+) respond with (?<response>[\S ]+)/i

	if when_trigger.match(text)
		match = when_trigger.match(text)
		puts match
		user = match[:user]
		if user.downcase == "i"
			user = from_user
		end

		trigger = match[:trigger]

		data = {
			user: user,
			trigger: trigger,
			response: match[:response]
		}

		puts data
		MongoDB["responses"].insert(data)

		return true
	end

	return false
end

def get_custom_response(from_user, text)
	all_responses = MongoDB["responses"]
	puts "Responses: #{all_responses}"
	all_responses.find.each do |row|
		puts row
		user = row["user"].downcase
		if user != "anyone" && user != from_user.downcase
			next
		end

		trigger = row["trigger"]
		r = Regexp.new("\\b#{trigger}\\b")
		if trigger == "anything" || r.match(text)
			return "<@#{from_user}> #{row["response"]}"
		end
	end

	return nil
end

def get_response(user, message)
	return nil if message == nil

	chastise_count = ChastiseList[user]
	if chastise_count != nil 
		if chastise_count == 0
			ChastiseList[user] = nil
		else
			ChastiseList[user] = chastise_count - 1
			return "<@#{user}> gfy"
		end
	end

	parts = message.split
	first = parts.first
	is_at = ((/<@#{UserID}>(:|,)?/i =~ first) || (/#{Name}(:|,)?/i =~ first))
	text = message 
	if is_at
		text = parts[1..parts.length].join " "
	end

	is_alex = (user == Alex)

	if custom_response = get_custom_response(user, text)
		return custom_response
	elsif is_at
		if set_custom_response(user, text)
			return "<@#{user}> you got it!"
		elsif /who are you\??/i =~ text
			return "a depressed robot"
		elsif /who is the (best|best person)\??/i =~ text
			return "<@#{Alex}> is"
		elsif /show me something (ridiculous|absurd)/ =~ text
			return Absurdity
		elsif /get me a gif/ =~ text
			search = /get me a gif (of |for )?(something |a )?(?<text>[\s+\w+ ]*)/i.match(text)
			return search_gif(search)
		elsif /get me (a |an )[\w+ ]* gif/i =~ text
			search = /get me (a |an )(?<text>[\w+ ]*) gif/i.match(text)
			return search_gif(search)
		elsif /(I )?(luv|love)e* (you|u)\!?/i =~ text
			if user == Alex
				return "gfy"
			else
				return ":heart_eyes:"
			end
		elsif /(meaning|answer) to life/ =~ text
			return "42"
		elsif /(how|what is|what’s|who’s|who is|what are|which)/i =~ text
			answer = answer_question text
			if answer != nil
				return answer
			else
				return "dunno, brah"
			end
		elsif /^tell me/ =~ text
			search = /^tell me(, | )?(?<question>[\w+]*)\??/i.match(text)
			puts search
			if search != nil
				question = search[:question]
				puts question
				return "<@#{user}> Thinking ................ #{Magic8Ball.sample}"
			end
		else
			puts "No command found for: #{text}"
		end
	elsif /what should I drink\?? (I want something( with)? ([\w ]+))?/i =~ text
		search = /what should I drink\?? (I want something( with)? (?<thing>[\w ]+))?/i.match(text)
		thing = search[:thing]
		if thing != nil
			cleaned = thing.gsub(/\band\b/i, "").gsub(/\bor\b/i, "").gsub(/\bwith\b/, "")
			thing = cleaned.split.join(" ").downcase
			return search_drink(user, thing)
		end
	elsif /\bkatie\b/i =~ text		
		strikes = StrikesPerUser[user] || 0
		strikes = strikes + 1
		StrikesPerUser[user] = strikes
		responses = [
			"<@#{user}> This is your first katie strike. 3 strikes and I'll yell at you for a while",
			"<@#{user}> DO YOU THINK THIS IS A MOTHERFUCKING GAME",
			"Since I can't kick you, you will now be chastised for a while."
		]

		response = responses[strikes-1]

		if strikes == 3
			StrikesPerUser[user] = 0
			ChastiseList[user] = 5
		end

		return response
	elsif /\bPaul\b/i =~ text
		return "<@#{user}> Pul*"
	end

	return nil
end

def send_message(client, channel, text)
	message = {}
	message["type"] = "message"
	message["channel"] = channel
	message["text"] = text

	client.send message
end

def can_shoot(message)
	/^shoot (<@\w+>|\w+)/i =~ message
end

def shoot(client, channel, person)
	num_steps = 15
	step = 0
	while step < num_steps
		spaces_before = " " * (num_steps - step)
		spaces_after = " " * step
		string = "#{person}#{spaces_before}・#{spaces_after}🔫 #{Name}"
		puts string
		send_message(client, channel, string)

		step = step + 1

		sleep(1.0/2.0)
	end
	final_string = "   :astonished:#{" " * num_steps}:gun: #{Name}"
	send_message(client, channel, final_string)
end

def respond_to_message(client, channel, user, message)
	return if message == nil

	response = get_response(user, message.downcase)
	if response != nil
		send_message(client, channel, response)
	else
		parts = message.split
		rest = parts[1..parts.length].join(" ")
		if can_shoot(rest)
			matches = /^shoot (?<person>(<@\w+>|\w+))/i.match(rest)
			person = matches[:person]
			puts "Shoot"
			shoot(client, channel, person)
		end
	end
end

client.on :message do |data|
	type = data["type"]
	if type == "message"
		respond_to_message client, data["channel"], data["user"], data["text"]
	end

	puts data
end

puts "Running"

client.main_loop
assert false # never
