# SCORE EPS to SVG converter

This Ruby script converts EPS files produced by Leland Smith's SCORE music typesetting software to SVG.

## Usage

    ruby seps2svg.rb EPSFILE

## Direct SVG

seps4id recognizes PostScript comments starting with `%svg%` as SVG code.

    %svg%<rect width="100" height="100"/>

seps2svg does not check whether the XML syntax is correct.  It copies whatever it finds to the output SVG verbatim.

To see some more detailed use cases for this feature, check out Craig Sapp's example pages:

* [color](http://score.sapp.org/example/8001/01/)
* [tooltips](http://score.sapp.org/example/8001/02/)
* [dynamic highlighting](http://score.sapp.org/example/8001/03/)

## Motivation

One motivation was to learn and use some Ruby in the context of a real world task.