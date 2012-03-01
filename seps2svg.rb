filename = ARGV[0]

$eps = File.new filename,"r"
$svg = File.new filename.downcase.gsub(".eps",".svg"),"w"

$programDirectory = File.dirname($0) + "/"
load $programDirectory + "fonttable.rb"
load $programDirectory + "standardEncoding.rb"

$glyphtable = {}
File.new($programDirectory + "glyphlist.txt","r").each_line {|line|
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
    $bb_left, $bb_bottom, $bb_right, $bb_top = line.gsub("%%BoundingBox:","").split.map{|value| value.to_i}
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
  $svg << %Q{     xmlns:xlink="http://www.w3.org/1999/xlink"\n}
  $svg << %Q{     viewBox="#{$bb_left} 0 #{$bb_right - $bb_left} #{$bb_top - $bb_bottom}"\n}
  $svg << %Q{     width="#{$bb_right - $bb_left}" height="#{$bb_top - $bb_bottom}">\n}
  $svg << %Q{<g transform="translate(0,#{$bb_top}) scale(1,-1) scale(#{$size}) translate(#{$lmar},#{$bmar})" }
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
      if $currentlw == $wdl then
        process_path(line,"")
      else
        process_path(line,%Q{stroke-width="#{$currentlw}"})
      end
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
    when /^\s*#{$re_number}\s+#{$re_number}\s+m\s+save\s*\(.*\)\s*show\s*$/o
      process_text(line)
    when /^\s*#{$re_number}\s+#{$re_number}\s+m\s+save\s*#{$re_number}\s+#{$re_number}\s+#{$re_number}\s+#{$re_number}\s+#{$re_number}\s*\(.*\)\s*aw\s*$/o
      process_text(line)
    when /^\s%svg%/
      process_direct_svg(line)
    when /\/acc(\[|\s|$)/
      set_encoding(line)
      unrecognized_code.clear
    when /^\s*newpath\s*#{$re_number}\s*#{$re_number}\s*#{$re_number}\s*-270\s*90\s*arc\s*$/o
      process_circle(line)
    # line of the form " g 1   2.00000 scale"
    when /^\s*g\s+1\s+#{$re_number}\s+scale\s*$/o
      process_ellipse(line)
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
  strokeWidth,dummy,x,y,scale,id = line.split
  write_use(strokeWidth, x, y, scale, id)
end

def process_small_use(line)
  # line of the form "  11112 -23650  1.000 P00"
  #                        0   1      2      3
  x,y,scale,id = line.split
  write_use($currentlw, x, y, scale, id)
end

def write_use(strokeWidth, x, y, scale,id)
  $svg << %Q{<use transform="translate(#{x},#{y})}
  if scale.to_f != 1 then
    $svg << %Q{ scale(#{scale})}
  end
  if strokeWidth != $wdl then
    $svg << %Q{" stroke-width="#{strokeWidth}}
  end
  $svg << %Q{" xlink:href="\##{id}"/>\n}
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
  def write_text_content(string)
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
    
    # if first character is a space, it is implicitly stripped by SVG, unless it's a non breaking space
    if (string[0]==" ") then
      $svg << "&#160;"
      string.slice!(0)
    end

    # Iterate through the glyphs. The regexp matches all single chars in literal PostScript strings.
    # Excption: A continuous whitespace sequence is also matched as it has to be treated specially
    string.scan(/\\n|\\r|\\t|\\b|\\f|\\\\|\\\(|\\\)|\\[0-3][0-7]{2}|\\.|\s+|./) { |c|
      if (c[/\s\s+/]) then
        c.each_char{$svg << "&#160;"}
      else
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
      end
    }
    
  end

  # line of the form "   7190  -20482 m save      .00 0 32    22.95 0 (cresc.) aw"
  #               or "     150  -23832 m save (Contrebasses) show"
  x,y = line.split
  $svg << %Q{<text transform="translate(#{x},#{y}) scale(1,#{-$current_y_size/$current_x_size})" fill="currentColor" stroke="none"}
  $svg << %Q{ font-size="#{$current_x_size}" #{$currentfont}>}
  string = line[/(?<=\()(.*)(?=\))/]
  if (string[/show\s*$/]) then
    write_text_content(string)
  else
    x,y,m,save,cx,cy,char,ax = line.split
    cx = cx.to_f
    ax = ax.to_f
    string.scan(/\s+|[^\s]+/) { |substring|
      $svg << %Q{<tspan }
      if (substring[/^s+$/]) then
        $svg << %Q{letter-spacing="#{ax + cx}">}
      else
        $svg << %Q{letter-spacing="#{ax}">}
      end
      write_text_content(substring)
      $svg << %Q{</tspan>}
    }
  end
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
  $svg << %Q{<circle cx="#{splitline[1]}" cy="#{splitline[2]}" r="#{splitline[3]}"}
  # in the next line, a single "e" (eofill) or "s" (stroke) is expected
  line = $eps.readline
  case line.strip
    when "e" then $svg << %Q{ fill="currentColor" stroke="none"}
    when "s" then ;
    else
      $warning_counter = $warning_counter+1
      print "WARNING #{$warning_counter}: Expected line with single 'e' or 's', but found:\n"
      puts line
  end
  $svg << %Q{/>\n}
end

def process_ellipse(line)
  #line of the form " g 1   2.00000 scale"
  yFactor = line.split[2].to_f
  line = $eps.readline
  #line of the form " newpath    2475.0  -12000.0     437.5 -270   90 arc"
  dummy,cx,rawCy,rx = line.split
  $svg << %Q{<ellipse cx="#{cx}" cy="#{rawCy.to_f * yFactor}" rx="#{rx}" ry="#{rx.to_f * yFactor}"}
  line = $eps.readline
  if (not line[/^\s*1\s+#{$re_number}\s+scale\s*$/]) then
    print %Q{WARNING #{$warning_counter}: Expected line of the form " 1    .50000 scale", but found:\n}
    puts line
  end
  line = $eps.readline
  case line
    when /^\s*e\s+r\s*$/ then $svg << %Q{ fill="currentColor"}
    when /^\s*s\s+r\s*$/ then ;
    else
      $warning_counter = $warning_counter+1
      print "WARNING #{$warning_counter}: Expected line with content 'e r' or 's r', but found:\n"
      puts line
    end
  $svg << %Q{/>\n}
end

def process_direct_svg(line)
  $svg << line.partition('%svg%')[2].chomp
  $svg << "\n"
end

root_element

print "\nSVG generation was successful with #{$warning_counter} warnings.\n"

#$encoding.each{|name| p name}