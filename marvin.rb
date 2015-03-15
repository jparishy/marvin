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

		MongoDB["responses"].insert(data)

		return true
	end

	return false
end

def get_custom_response(from_user, text)
	all_responses = MongoDB["responses"]
	all_responses.find.each do |row|
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

def get_reddit_random(user, text)
	regex = /^(get( me)? a )?random post (in|from) (?<sub>(\S+))/i
	match = regex.match(text)
	if match != nil
		sub = match[:sub]
		path = "http://api.reddit.com/r/#{sub}/?sort=random"
		response = HTTParty.get path
		json = JSON.load(response.body)

 		if json == nil
 			return "I ain't find nuttin'"
 		end
 
 		data = json["data"]

 		if data.count == 0
 			return "I ain't find nuttin'"
 		end
 
 		children = data["children"]
 		if children == nil
 			return "I ain't find nuttin'"
 		end
 
 		if children.count == 0
 			return "I ain't find nuttin'"
 		end

		i = 10
		while i > 0
			child = children.sample
			url = child["data"]["url"]

			if /(jpg|gif|gifv|png)$/i =~ url
				return "<@user> #{url}"
			end

			i = i - 1
		end
	end

	return nil
end

def set_macros(user, message)
	regex = /set my (?<day>\w+) day macros to P(?<protein>\d{1,3}) C(?<carbs>\d{1,3}) F(?<fat>\d{1,3})/i
	match = regex.match(message)
	if match != nil
		day = match[:day]
		protein = match[:protein]
		carbs = match[:carbs]
		fat = match[:fat]

		old_macros = MongoDB["macros"].find({ user: user })
		old_macros.each do |om|
			om[:is_current] = false
			MongoDB["macros"].update({ "_id" => om["_id"] }, om)
		end

		date = Time.now.utc

		new_macros = {
			user: user,
			day: day,
			protein: protein,
			carbs: carbs,
			fat: fat,
			date: date,
			is_current: true
		}

		MongoDB["macros"].insert(new_macros)
		return "<@#{user}> I set your #{day} macros to P#{protein} C#{carbs} F#{fat}"
	end

	return nil
end

def get_macros(user, text)
	regex = /what are my( (?<day>\w+)( day)?)? macros\??/i
	match = regex.match(text)
	if match != nil
		day = match[:day] || "lifting"
		macros = MongoDB["macros"].find({ user: user, is_current: true, day: day }).to_a
		if macros.count == 0
			return "You haven't set your #{day} day macros yet.\nYou can set them by telling me '#{Name} set my <day> macros to P<protein> C<carbs> F<fat>'"
		else
			m = macros.first
			return "<@#{user}> your current #{day} macros are P#{m["protein"]} C#{m["carbs"]} F#{m["fat"]} (you set them: #{m["date"]})"
		end
	end

	return nil
end

def set_weight(user, text)
	regex = /set my weight to (?<weight>\d*.\d{1,2})/i
	match = regex.match(text)
	if match != nil
		weight = match[:weight]

		old_weights = MongoDB["weight"].find({ user: user })
		old_weights.each do |ow|
			ow[:is_current] = false
			MongoDB["weight"].update({ "_id" => ow["_id"] }, ow)
		end

		date = Time.now.utc

		new_weight = {
			user: user,
			weight: weight,
			date: date,
			is_current: true
		}

		MongoDB["weight"].insert(new_weight)
		return "<@#{user}> I set your weight to #{weight}"
	end

	return nil
end

def get_weight(user, text)
	regex = /what.?s my current weight\??/i
	match = regex.match(text)
	if match != nil
		weights = MongoDB["weight"].find({ user: user, is_current: true }).to_a
		if weights.count == 0
			return "You haven't set your weight yet!\nYou can set it by saying '#{Name}' set my weight to <weight>"
		else
			m = weights.first
			return "<@#{user}> your current weight is #{m["weight"]}"
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
		if weight = set_weight(user, text)
			return weight
		elsif weight = get_weight(user, text)
			return weight
		elsif macros = set_macros(user, text)
			return macros
		elsif macros = get_macros(user, text)
			return macros
		elsif set_custom_response(user, text)
			return "<@#{user}> you got it!"
		elsif response = get_reddit_random(user, text)
			return response
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
			if search != nil
				question = search[:question]
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
