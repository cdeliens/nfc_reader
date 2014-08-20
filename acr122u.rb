require 'smartcard'
require 'uri'
require 'redis'
require 'mechanize'

uri = URI.parse("redis://localhost:6379/")
$redis = Redis.new(:host => uri.host, :port => uri.port, :password => uri.password)

context = Smartcard::PCSC::Context.new
reader = context.readers.first

queries = Smartcard::PCSC::ReaderStateQueries.new(1)
queries[0].current_state = :empty
queries[0].reader_name = context.readers.first
agent = Mechanize.new{ |agent| agent.follow_meta_refresh = true}

route_a = [[9.857770, -83.924975],[9.858636, -83.926520],[9.861850, -83.924996],[9.863604, -83.924910],[9.863752, -83.925855],[9.866226, -83.925425],[9.866205, -83.924460],[9.866945, -83.924331],
[9.865507, -83.914160],[9.860518, -83.914761],[9.859482, -83.913023],[9.858235, -83.913388],[9.858784, -83.917336],[9.857199, -83.915834],[9.857770, -83.924975],[9.854556 -83.919482]]
index = 0

loop do
  context.wait_for_status_change(queries)
  queries.ack_changes
  

  begin
    card = context.card(reader, :shared)

    # Ask card for UID in APDU format (Section 5.1)
    response = card.transmit("\xFF\xCA\x00\x00\x04").unpack('C*')

    # # Beep and change LED to orange to signal user we've read the tag.
    # # (Section 6.2)
    # card.transmit "\xFF\x00\x40\xCF\x04\x03\x00\x01\x01" rescue nil

    # Check last two bytes for success code
    if response.last(2) == [0x90, 00]
      # Nice hex string
      uid = response[0..-3].pack('C*').unpack('H*').first
      response = agent.get "http://icanhazip.com"
      $redis.set "NFC_Tracker_Route_A.#{uid}#{Time.now.strftime("%F%H%M%S%L")}", {name: "route_a", position: index, id: uid, status: "read", time: Time.now.strftime("%F-%H-%M-%S-%L"), ip: response.body, latitude: route_a[index][0], longitude: route_a[index][1]}
      puts "TAG: #{uid}, latitude: #{route_a[index][0]}, longitude: #{route_a[index][1]}"
      index += 1
      if (index + 1) == route_a.count
        index = 0
        puts "reseting index"
      end

    else
      puts 'ERROR: tag error when reading UID'
    end
  rescue Smartcard::PCSC::Exception => ex
    puts "ERROR: #{ex.pcsc_status}"
  end

  context.wait_for_status_change(queries)   # Wait for tag to be removed
  queries.ack_changes
end



