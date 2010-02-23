require 'rubygems'
require 'net/imap'
require 'net/http'
require 'tmail'
require 'pivotal-tracker'
require 'ruby-debug'

TRACKER_PROJECT_ID = 24159 #57337 is Chronus Rythm
TRACKER_API_TOKEN = 'a958b88686876e701169de774093c0ad' #This is Mrudhukar's API Token
USER_NAME = "pivotaltracker@chronus.com"
PASSWORD = "Chr0nus1"

class PivotalTrackerStory

  class << self
    def add_pt_story(project, source)
      puts "**Initiating pt story add**" 
      email_object = TMail::Mail.parse(source)
      to_adresses = email_object.to.select{|add| add =~ /pivotaltracker.*?@chronus\.com/}

      unless to_adresses.any? && email_object.from[0] =~ /@chronus\.com/
        puts "**Not a valid story**"
        return false
      end
      email = email_object.to_s

      subject   = email.scan(/Subject: (.*)/).flatten.first
      to        = email.scan(/To: (.*)/).flatten.first
      body      = email_object.body.split("\r\n\r\n").first + "\n\n -- This story is added via email"
      from_name = parse_name(email)
      cc_name   = parse_cc_name(email)

      story = Story.new
      story.story_type   = get_story_type_from_email_address(to)
      story.description  = get_description(body)
      story.name         = subject
      story.requested_by = from_name
      story.owned_by = cc_name if cc_name

      created_story = project.create_story(story)
      puts "**Sucessfully added**"
    end

    def get_description(body)
      # Tracker has a max_len for description and comments
      # Split up the email body into chunks; use the first one as the description
      #TODO and add the remainder as comments
      chunks = body.split(/(.{5000})/m).reject{|token| token.nil? || token.length==0}
      return chunks[0]
    end

    def parse_cc_name(email)
      cc = email.scan(/Cc: \"(.*)\"/).flatten.first || email.scan(/Cc: (.*) \</).flatten.first
      cc.gsub(/[\"\\]/,'') if cc
    end

    # This will regex the name from the following formats so far:
    # From: "Benjamin Stein" <ben@mcommons.com>
    # From: Benjamin Stein <ben@mcommons.com>
    def parse_name(email)
      email.scan(/From: \"(.*)\"/).flatten.first || email.scan(/From: (.*) \</).flatten.first
    end

    def get_story_type_from_email_address(address)
      case address
      when /feature/ then :feature
      when /bug/     then :bug
      when /chore/   then :chore
      else                :feature
      end
    end

  end
end

puts Time.now
begin
  puts "**Logging in**"
  imap = Net::IMAP.new('imap.gmail.com','993',true)
  imap.login(USER_NAME, PASSWORD)
  pt_project = PivotalTracker.new(TRACKER_PROJECT_ID, TRACKER_API_TOKEN)

  if imap.status("inbox", ["UNSEEN"])["UNSEEN"] > 0
    imap.select('Inbox')
    email_uids = imap.uid_search(["NOT", "SEEN", "TO", USER_NAME])

    email_uids.each do |uid|
      # fetches the straight up source of the email for tmail to parse
      source   = imap.uid_fetch(uid, ['RFC822']).first.attr['RFC822']
      PivotalTrackerStory.add_pt_story(pt_project, source)

      # there isn't move in imap so we copy to new mailbox and then delete from inbox
      imap.uid_copy(uid, "[Gmail]/All Mail")
      imap.uid_store(uid, "+FLAGS", [:Deleted])
    end
    #FIXME expunge premenantly removes the deleted emails
    # imap.expunge
  else
    puts "**No unread messages**"
  end

  imap.logout
  imap.disconnect
  puts "**Successfull logged out**"
  # NoResponseError and ByResponseError happen often when imap'ing
rescue Net::IMAP::NoResponseError => e
  # send to log file, db, or email
rescue Net::IMAP::ByeResponseError => e
  # send to log file, db, or email
end
