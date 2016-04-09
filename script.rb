require "pry"
require "mail"
require "redis"
require "base64"
require "nokogiri"
require "open-uri"
require "digest/md5"
require 'unicode_utils'
require "active_support"
require "active_support/core_ext"

NBSP    = Nokogiri::HTML("&nbsp;").text
# uri     = "https://999.md/ru/list/agriculture/grain-cereals-flours?query=rasarita"
uri     = "https://999.md/ru/list/transport/bicycles?applied=1&ef=336&o_336_1=776&ef=337&o_337_7=12900&ef=1129&o_1129_649=7298&ef=3395&o_3395_593=6371"
# uri     = "https://999.md/ru/list/real-estate/apartments-and-rooms?applied=1&ef=32&eo=12900&eo=13859&o_32_9_12900_13859=15667&ef=33&o_33_1=776&ef=2203&ef=2307&ef=1074&o_1074_253=931&ef=31&r_31_2_from=30000&r_31_2_to=45000&r_31_2_unit=eur&ef=1075&o_30_241=894&ef=1191&o_1191_248=935&o_1191_248=905&o_1191_248=929&ef=1192&o_1192_249=910&o_1192_249=919&ef=1197&o_1197_250=920&o_1197_250=933"
html    = Nokogiri::HTML(open(uri))
redis   = Redis.new
data    = {}
counter = 0

def normalize_string(string)
  return "" if string.nil?
  string.gsub(NBSP, " ").gsub(/[−–]/, "-").squeeze(' ').strip
end

def parse_description(string)
  normalize_string(string.gsub(/[\s]/, ' '))
end

html.css("li.ads-list-photo-item").select { |li| li.css(".ads-list-photo-item-price").present? }.each_with_index do |item, index|
  break if counter >= 5
  index              = "item_#{index}".to_sym
  data[index]        = {}
  data[index][:name] = item.css("div.ads-list-photo-item-title").text
  hash               = Digest::MD5.hexdigest(Marshal::dump(data[index][:name]))
  if redis.get(hash)
    next
  else
    redis.set(hash, "1")
  end

  data[index][:name]  = item.css("div.ads-list-photo-item-title").text
  data[index][:price] = item.css(".ads-list-photo-item-price").text

  html = Nokogiri::HTML(Net::HTTP.get(URI("https://999.md#{item.css("a").first.attr("href")}")))
  puts "https://999.md#{item.css("a").first.attr("href")}"

  data[index][:url] = "https://999.md#{item.css("a").first.attr("href")}"
  body = html.css("div.adPage__content__description.grid_18").text
  body = body.split("TAGS:").first if body.include?("TAGS:")
  data[index][:body] = parse_description(body)

  data[index][:pictures] = []
  html.css("div.adPage__content__photos__item").each do |photo_src|
    data[index][:pictures] << photo_src.css("img").attr("src").value.gsub("160x120", "900x900")
  end

  lis = html.css("div.adPage__content__features__col.grid_9.suffix_1 li")
  data[index][:extra] = lis.inject({}) { |hash, li| hash[parse_description(li.css("span").first.text)] = parse_description(li.css("span").last.text); hash }

  options = {
    :address              => "smtp.gmail.com",
    :port                 => 587,
    :domain               => 'your.host.name',
    :user_name            => 'Edchekushkin@gmail.com',
    :password             => 'label300',
    :authentication       => 'plain',
    :enable_starttls_auto => true
  }

  Mail.defaults do
    delivery_method :smtp, options
  end

  b    = binding
  mail = Mail.new do
    # to("danil.lunev@gmail.com")
    to("edchekushkin@gmail.com")
    # to("skitishsmile@gmail.com")
    from("test@test.com")
    subject(data[index][:name])
  end

  html_part = Mail::Part.new do
    content_type("text/html; charset=UTF-8")
    body(ERB.new("
        <h1 align='center'><%= data[index][:price] %></h1>
        <h2 align='center'><%= data[index][:url] %></h2>
        <font style='line-height:normal;' size='3'> <%= data[index][:body] %> </font>
        <p></p>
        <table>
          <% data[index][:extra].each do |key, value| %>
            <tr>
              <td> <%= key %> ... <%= value %> </td>
            <tr>
          <% end %>
        </table>
        ", 0, "",  "abc").result b
      )
  end

  mail.part :content_type => "multipart/alternative" do |p|
    p.html_part = html_part
  end

  unless data[index][:pictures].blank?
    data[index][:pictures].each_with_index do |img_url, index|
      mail.attachments["#{index}.jpg"] = {
        :mime_type => 'image/jpeg',
        :content => open(img_url).read
      }
    end
  end


  mail.content_type = mail.content_type.gsub('alternative', 'mixed')
  mail.charset= 'UTF-8'
  mail.content_transfer_encoding = 'quoted-printable'

  mail.deliver!
  counter += 1
end
