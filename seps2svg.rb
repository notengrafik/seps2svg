filename = ARGV[0]

$eps = File.new filename,"r"
$svg = File.new filename.downcase.gsub(".eps",".svg"),"w"

load "fonttable.rb"
load "standardEncoding.rb"

$glyphtable = {}
File.new("glyphlist.txt","r").each_line {|line|
  line.strip!
  if line[0]!="#" then
    line = line.split ";"
    $glyphtable[line[0].strip] = line[1].to_i(16)
  end
}

# Regular expression constants ("re_...")

# Why doesn't this work?
# $re_delimiter = /[\s\(\)<>\[\]\{\}\/%]/
# $re_number = /(^|(?<=#{$re_delimiter}))([+-]?\d*(\.\d+|\d\.|\d)([eE][+-]?)?\d*|\d+#[\da-fA-F]*)($|(?=#{$re_delimiter}))/
# $re_psname = /(^|(?<=#{$re_delimiter}))(?!#{$re_number})[^\s\(\)<>\[\]\{\}\/%]+($|(?=#{$re_delimiter}))/
# Why does this have to be in parentheses: (.*\)

$re_number = /(^|(?<=[\s\(\)<>\[\]\{\}\/%]))([+-]?\d*(\.\d+|\d\.|\d)([eE][+-]?)?\d*|\d+#[\da-fA-F]*)($|(?=[\s\(\)<>\[\]\{\}\/%]))/
$re_psname = /(^|(?<=[\s\(\)<>\[\]\{\}\/%]))(?!#{$re_number})[^\s\(\)<>\[\]\{\}\/%]+($|(?=[\s\(\)<>\[\]\{\}\/%]))/

# TODO: Do better checking of the lines in header rather than blindly assuming correct form

# read parameters for global gstate
# search for BoundingBox
$eps.each_line { |line|
  if line["%%BoundingBox:"] then
    name_dummy, $bb_llx,$bb_lly,$bb_urx,$bb_ury = line.split.collect{|coordinate| coordinate.to_i}
    # (The first element in the split array is "%%BoundingBox:" and gets converted to name_dummy=0)
    break
  end
}


# search for /SCORE
$eps.each_line { |line| if line[/^\s*newpath \/SCORE  \{\s*$/] then break end}
# read /size and /wdl values from next line
splitline = $eps.readline.split
$size = splitline[1]
$wdl = splitline[4]
$currentlw = $wdl
$currentfont = ""
$current_x_size = 0
$current_y_size = 0
$warning_counter = 0


# skip line
$eps.readline

# read /lmar and /bmar values from next line
splitline = $eps.readline.split
$lmar = splitline[1]
$bmar = splitline[4]

# skip line
 2.times{$eps.readline}


def root_element
  $svg << %Q{<?xml version="1.0"?>\n}
  $svg << %Q{<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN"\n}
  $svg << %Q{  "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">\n\n}
  $svg << %Q{<svg version="1.1"\n}
  $svg << %Q{     xmlns="http://www.w3.org/2000/svg"\n}
  $svg << %Q{     xmlns:xlink="http://www.w3.org/1999/xlink"}
  $svg << %Q{     width="#{$bb_urx - $bb_llx}" height="#{$bb_ury - $bb_lly}">\n}
  $svg << %Q{<g transform="translate(#{-$bb_llx},#{$bb_ury}) scale(1,-1) scale(#{$size}) translate(#{$lmar},#{$bmar})" }
  $svg << %Q{stroke-linejoin="round" color="black" stroke="currentColor" fill="none" stroke-width="#{$wdl}"  fill-rule="evenodd">\n}

  process_eps

  $svg << "</g>\n"
  $svg << "</svg>\n"
end


def process_eps
  # TODO:
  # - Recognize outline fonts
  # - Process text using "aw"
  unrecognized_code = ""

  $eps.each_line { |line|
    recognized = true

    case line
    # line of the form " /EXEC{/exec load}bind def /P00[{g /z exch def /y exch def /x exch def x y tr  z z scale"
    when /^\s*\/EXEC\{\/exec load\}bind def \/P\d*\[\{g \/z exch def \/y exch def \/x exch def x y tr  z z scale/
      process_def(line)
    # line of the form "118 -168 m"
    when /^\s*#{$re_number}\s+#{$re_number}\s+m\s*$/o
      process_path(line,%Q{stroke-width="#{$currentlw}"})
    # line of the form "  55.639 lw   3743 -24000   .480 P04 wdl lw"
    when /^\s*#{$re_number}\s+lw\s+#{$re_number}\s+#{$re_number}\s+#{$re_number}\s+P\d+\s+wdl lw\s*$/o
      process_use(line)
      $currentlw = $wdl
    # line of the form "  11112 -23650  1.000 P00"
    when /^\s*#{$re_number}\s+#{$re_number}\s+#{$re_number}\s+P\d+\s*$/o
      process_small_use(line)
      $currentlw = $wdl
    # line of the form "20.0300 lw"
    when /^\s*#{$re_number}\s+lw\s*$/o
      $currentlw = line.split[0]
    # line of the form "/EXEC {/exec load } bind def /trl ["
    when /^\s*\/EXEC \{\/exec load \} bind def \/trl \[\s*$/
      def_trill
    # line of the form "15540.3 -17970.0  16950.0    144.5 trl"
    when /^\s*#{$re_number}\s+#{$re_number}\s+#{$re_number}\s+#{$re_number}\s+trl\s*$/o
      process_trill(line)
    # line of the form "/Times-Roman                  f [   485.082 0 0   485.082 0 0] mkf sf"
    when /^\s*\/#{$re_psname}\s+f \[\s*#{$re_number}\s+0\s+0\s+#{$re_number}\s+0\s+0\] mkf sf\s*$/o
      set_font(line)
    # line of the form "     150  -23832 m save (Contrebasses) show"
    when /^\s*#{$re_number}\s*#{$re_number}\s*m save \(.*\) show\s*$/o
      process_text(line)
    when /\/acc(\[|\s|$)/
      set_encoding(line)
      unrecognized_code.clear
    # elsif line.strip == ""
    # Metadata tag of the form %OBJECT:ID=4:START:17. 1.0  19.459    .0  -5.00    .00    .8500
    when /^\s*%OBJECT:ID=\d*:START:/
      $svg << %Q{<g>\n}
    when /^\s*%OBJECT:ID=\d*:END:/
      $svg << %Q{</g>\n}
    when /^\s*newpath\s*#{$re_number}\s*#{$re_number}\s*#{$re_number}\s*-270\s*90\s*arc\s*$/o
      process_circle(line)
    else
      recognized = false
      unrecognized_code << line
    end
    if recognized && !unrecognized_code.empty? then
      $warning_counter = $warning_counter+1
      print "WARNING #{$warning_counter}: unrecognized EPS code:\n"
      print unrecognized_code
      unrecognized_code.clear
    end
  }
end


def def_trill
  $svg << %Q{<defs>\n}
  $svg << %Q{<g id="trl">\n}
  # skip 2 lines
  2.times{$eps.readline}
  line = $eps.readline
  process_path(line,'fill="currentColor"')
  $svg << %Q{</g>\n}
  $svg << %Q{</defs>\n}
end

def process_trill(line)
  r3, r4, r6, z = line.split
  r3 = r3.to_f
  r4 = r4.to_f
  r6 = r6.to_f
  z = z.to_f
  $svg << %Q{<g stroke-width="#{$currentlw}">\n}
  #((r6-r3)/z).floor.times{ |n|
  ((r6-r3)/z).ceil.times{ |n|
    x = r3 + n*z
    $svg << %Q{<use transform="translate(#{x},#{r4})" xlink:href="#trl"/>\n}
  }
  $svg << %Q{</g>\n}
end

def process_use(line)
  # line of the form "  55.639 lw   3743 -24000   .480 P04 wdl lw"
  #                        0   1     2      3       4   5   6   7
  splitline=line.split
  $svg << %Q{<use stroke-width="#{splitline[0]}" transform="translate(#{splitline[2]},#{splitline[3]}) scale(#{splitline[4]})" }
  $svg << %Q{xlink:href="\##{splitline[5]}"/>\n}
end

def process_small_use(line)
  # line of the form "  11112 -23650  1.000 P00"
  #                        0   1      2      3
  splitline=line.split
  $svg << %Q{<use stroke-width="#{$currentlw}" transform="translate(#{splitline[0]},#{splitline[1]}) scale(#{splitline[2]})" }
  $svg << %Q{xlink:href="\##{splitline[3]}"/>\n}
end

def process_def(line)
  $svg << %Q{<defs>\n}
  $svg << %Q{<g id="#{line[/P\d*/]}">\n}
  line = $eps.readline
  begin
    process_path(line,"")
  end while (line = $eps.readline) =~ /^\s*#{$re_number}\s+#{$re_number}\s+m\s*$/o
  $svg << %Q{</g>\n}
  $svg << %Q{</defs>\n}
end


def process_path(line, attributes)
  $svg << %Q{<path #{attributes} d="\n}
  begin
    # write M or L and coordinates
#    print "before upcase: " + line
    splitline=line.split
    $svg << "#{splitline[2].upcase}#{splitline[0]} #{splitline[1]}\n"
    begin
      line = $eps.readline
    end while line=~/\s*} EXEC {\s*/
  end while line=~ /^\s*#{$re_number}\s+#{$re_number}\s+[ml]\s*$/o
#  print "path done\n"
  # if final line of path is "g e r s", then path is filled => set fill attribute
  if line =~ /^\s*g e r s\s*$/ then
    $svg << 'Z" fill="currentColor'
  end
  $svg << %Q{"/>\n}
end

def set_encoding(line)
  # Position file cursor right after "/acc"
  $eps.seek(-(line[/(?<=\/acc)[\[|\s|$].*$/].length),IO::SEEK_CUR)
  $eps.each_char {|c|
    if c=="[" then
      break
    end
  }

  # Store whole PostScript array defintion in one string
  s=""
  $eps.each_char { |c|
    if c == "]" then
      break
    end
    if c == "%" then   # skip comments
      $eps.readline
      s << "\n"
    else
      s << c
    end
  }

  while !s.empty?
    s.lstrip!
    # next expected token is a PS integer (decimal or octal form)
    substring = s[/^(8#)?[0-9]+/]
    if !substring then
      $warning_counter = $warning_counter+1
      print "WARNING #{$warning_counter}: Couldn't complete parsing encoding vector.\nPostScript integer expected, but found:\n"
      puts s
      break
    end
    if substring[/^8#/] then
      code = substring[2..-1].to_i(8)
    else
      code = substring.to_i
    end
    s = s[substring.length,s.length-1].lstrip # remove parsed number
    # next expected token is a PS name

    name = s[/(?<=^\/)#{$re_psname}/o]
    if !name then
      $warning_counter = $warning_counter+1
      print "WARNING #{$warning_counter}: Couldn't complete parsing encoding vector.\nPostScript name with leading slash expected, but found:\n"
      puts s
      break
    end
    $encoding[code] = name
    s = s[name.length+1,s.length-1].lstrip # remove parsed name
  end

  # skip rest of fontinit.psc
  $eps.each_line {|s|
    if s["this must be here to end the file"] then
      break
    end
  }
end

def set_font(line)
  # TODO: Error handling if font information wasn't found
  ps_fontname = line[$re_psname]
  $currentfont = $fonttable[ps_fontname]
  line = line.split
  $current_x_size = line[3].to_i
  $current_y_size = line[6].to_i
end

def process_text(line)
  # TODO: Define precise character positions using x-Attribute

  def write_unicode_glyph(ps_glyph_code)
    c = $glyphtable[$encoding[ps_glyph_code]]
    # if c is undefined, write a kind of missing-glyph rectangle
    if !c
      $svg << "&#9647;"
    # check whether c is in the printable ASCII range
    # (and not "<" which would be interpreted as a tag bracket)
    elsif (c>31) && (c<127) && (c!="<".ord)
      $svg << c.chr
    elsif # write Unicode
      $svg << "&#" << c << ";"
    end
  end

  string = line[/(?<= m save \()(.)*(?=\) show\s*$)/]
  line = line.split
  x = line[0]
  y = line[1]

  $svg << %Q{<text transform="translate(#{x},#{y}) scale(#{$current_x_size},#{-$current_y_size})" fill="currentColor" stroke="none" }
  $svg << %Q{ font-size="1" #{$currentfont}>}

  # Iterate through the glyphs. The regexp matches all single chars in literal PostScript strings.
  string.scan(/\\n|\\r|\\t|\\b|\\f|\\\\|\\\(|\\\)|\\[0-3][0-7]{2}|\\.|./) { |c|
    case c.length
      when 1 then write_unicode_glyph(c[0].ord)
      when 2 then case c[1]
        when "n" then write_unicode_glyph(10)
        when "r" then write_unicode_glyph(13)
        when "t" then write_unicode_glyph(9)
        when "b" then write_unicode_glyph(8)
        when "f" then write_unicode_glyph(12)
        when "\\" then write_unicode_glyph(92)
        when "(" then write_unicode_glyph(40)
        when ")" then write_unicode_glyph(41)
        else write_unicode_glyph(c[1].ord)
      end
      # octal codes
      when 4 then write_unicode_glyph(c[1,3].to_i(8))
    end
  }

  $svg << %Q{</text>\n}

  line = $eps.readline
  if (not line[/^\s*restore\s*$/]) then
    print "WARNING #{$warning_counter}: Unexpected line after Text item:\n"
    puts line
  end
end

def process_circle(line)
  # line of the form " newpath   15487.5  -23475.0      50.8 -270   90 arc"
  splitline = line.split
  $svg << %Q{<circle cx="#{splitline[1]}" cy="#{splitline[2]}" r="#{splitline[3]}" stroke="none" fill="currentColor"/>\n}
  # in the next line, a single "e" (eofill) is expected
  line = $eps.readline
  if line !~ /^\s*e\s*$/ then
    $warning_counter = $warning_counter+1
    print "WARNING #{$warning_counter}: Expected line with single 'e', but found:\n"
    puts line
  end
end

root_element

print "\nSVG generation was successful with #{$warning_counter} warnings.\n"

#$encoding.each{|name| p name}