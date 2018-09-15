require 'pry'
require 'mail'
require 'redis'
require 'base64'
require 'nokogiri'
require 'open-uri'
require 'digest/md5'
require 'unicode_utils'
require 'active_support'
require 'active_support/core_ext'

ARR_MOTH = [
  'января Январь',
  'февраля Февраль',
  'марта Март',
  'апреля Апрель',
  'мая Май',
  'июня Июнь',
  'июля Июль',
  'августа Август',
  'сентября Сентябрь',
  'октября Октябрь',
  'ноября Ноябрь',
  'декабря Декабрь'
].freeze

NBSP  = Nokogiri::HTML('&nbsp;').text
# NOTE: ads should be in short description view
uri   = 'https://999.md/ru/list/clothes-and-shoes/watches?applied=1&view_type=short&ef=2013&ef=2017&ef=2019&o_2013_1=776&query=apple+watch+3&o_2017_620=18910'
html  = Nokogiri::HTML(open(uri))
redis = Redis.new
data  = {}

def self.get_index(string)
  string = UnicodeUtils.downcase(string)
  ARR_MOTH.each_with_index do |element, index|
    return index if UnicodeUtils.downcase(element).split.any? { |month| month[/#{string}/] }
  end
  ARR_MOTH.each_with_index do |element, index|
    return index if UnicodeUtils.downcase(element)[/#{string}/]
  end
  nil
end

def convert(string)
  date      = string[/[a-z]+|[а-я]+/i]
  month_int = format('%02d', (get_index(date) + 1))
  string.gsub(date, month_int)
end

def normalize_string(string)
  return '' if string.nil?
  string.gsub(NBSP, ' ').gsub(/[−–]/, '-').squeeze(' ').strip
end

def parse_description(string)
  normalize_string(string.gsub(/[\s]/, ' ')).split('.').map(&:capitalize).map(&:strip).join('. ')
end

counter = 0
html.css('table.ads-list-table tr').select do |tr|
  tr.css('.ads-list-table-price').present? && !tr.css('.ads-list-table-price').text.blank?
end.each_with_index do |item, index|
  index               = "item_#{index}".to_sym
  data[index]         = {}
  data[index][:name]  = parse_description(item.css('a').text)
  data[index][:price] = item.css('td.ads-list-table-price').text
  hash                = Digest::MD5.hexdigest(Marshal.dump(data[index][:name] + data[index][:name]))

  if redis.get(hash)
    puts 'already parsed'
    next
  else
    redis.set(hash, '1')
  end

  counter += 1
  return if counter > 3

  html = Nokogiri::HTML(Net::HTTP.get(URI("https://999.md#{item.at_css('a')['href']}")))

  puts html.css('dd').detect { |dd| dd.text.match(/^\d{1,2}/) }.text.split(',').first
  date = Date.strptime(convert(html.css('dd').detect { |dd| dd.text.match(/^\d{1,2}\s/) }.text.split(',').first.delete('.')), '%d %m %Y')

  puts "https://999.md#{item.at_css('a')['href']}"
  puts date.to_s
  next if date < 1.month.ago.to_date

  data[index][:url]  = "https://999.md#{item.at_css('a')['href']}"
  body               = html.css('div.adPage__content__description.grid_18').text
  body               = body.split('TAGS:').first if body.include?('TAGS:')
  data[index][:body] = parse_description(body)

  data[index][:pictures] = []
  html.css('div.adPage__content__photos__item').each do |photo_src|
    data[index][:pictures] << photo_src.css('img').attr('src').value.gsub('160x120', '900x900')
  end

  lis                 = html.css('div.adPage__content__features__col.grid_9.suffix_1 li')
  data[index][:extra] = lis.each_with_object({}) do |li, hash|
    hash[parse_description(li.at_css('span').text)] = parse_description(li.css('span').last.text)
  end

  if html.css('dl.adPage__content__region.grid_18').present?
    data[index][:adress] = parse_description(html.css('dl.adPage__content__region.grid_18').text.gsub(/Регион:/, '')).gsub(' ,', ',')
  end

  unless html.css('div.adPage__content__features__col.grid_7.suffix_1 li').blank?
    data[index][:additional] = []
    html.css('div.adPage__content__features__col.grid_7.suffix_1 li').each do |li|
      data[index][:additional] << parse_description(li.text)
    end
  end

  options = {
    address:              'smtp.gmail.com',
    port:                 587,
    domain:               'your.host.name',
    user_name:            'ed********@gmail.com',
    password:             '*******',
    authentication:       'plain',
    enable_starttls_auto: true
  }

  Mail.defaults do
    delivery_method :smtp, options
  end

  b    = binding
  mail = Mail.new do
    to('ed********@gmail.com')
    from('ed********@test.com')
    subject(data[index][:name] + '999ads')
  end

  html_part = Mail::Part.new do
    content_type('text/html; charset=UTF-8')
    body(ERB.new("
        <style>
        .header-big {
            font-family:'HelveticaNeue-UltraLight', 'HelveticaNeue-Light', 'Helvetica Neue Light', 'Helvetica Neue', Helvetica, Arial, 'Lucida Grande', sans-serif;
            font-size: 30px;
            color: #005284;
        }
        body {
            background-color: #e6e6e6;
        }
        .price-style {
            font-family: 'HelveticaNeue-Light', Arial;
            font-size: 35px;
            color: #ff0000;
        }
        .uri-style {
            font-family: 'HelveticaNeue-Light', Arial;
            font-size: 15px;
            color: #005284;
        }
        .adress-style {
            font-family: 'HelveticaNeue-Light', 'Open Sans', Arial;
            font-size: 20px;
            color: black;
        }
        .body-style {
            font-family: 'HelveticaNeue-Light', 'Open Sans', Arial;
            font-size: 15px;
            color: black;
        }
        </style>
        <div class='header-big' align='center'><%= data[index][:name] %></div>
        <div class='price-style' align='center'><%= data[index][:price] %></div>
        <div class='adress-style' align='center'><%= data[index][:url] %></div>
        <div class='uri-style' align='center'><%= data[index][:adress] %></div>

        <div class='body-style'><%= data[index][:body] %></div>
        <p></p>

        <table class='body-style' align='left'>
          <% unless data[index][:extra].blank? %>
            <% data[index][:extra].each do |key, value| %>
              <tr>
                <td> <%= key %> ... <%= value %> </td>
              <tr>
            <% end %>
          <% end %>
        </table>
        <table class='body-style' align='right'>
          <% unless data[index][:additional].blank? %>
            <% data[index][:additional].each do |item| %>
              <tr>
                <td><%= item %></td>
              <tr>
            <% end %>
          <% end %>
        </table>
        ", 0, '', 'abc').result(b))
  end

  mail.part content_type: 'multipart/alternative' do |p|
    p.html_part = html_part
  end

  unless data[index][:pictures].blank?
    data[index][:pictures].each_with_index do |img_url, index|
      mail.attachments["#{index}.jpg"] = {
        mime_type: 'image/jpeg',
        content:   open(img_url).read
      }
    end
  end

  mail.content_type              = mail.content_type.gsub('alternative', 'mixed')
  mail.charset                   = 'UTF-8'
  mail.content_transfer_encoding = 'quoted-printable'

  mail.deliver!
end
