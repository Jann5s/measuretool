# Measure Tool

Measure Tool is a matlab function (measuretool.m) that provides a Graphical User Interface (GUI) that is designed to aid measurements on images.

If an image contains some visible object of known length, for example, a scale bar or a ruler, then the physical size of an area as imaged by a pixel (i.e. the pixel size) can be calibrated. This tool provides tools to perform this calibration (draw a line on the ruler) and then perform measurements on the image:
- Distance: point-point distance
- Caliper: line-point perpendicular distance
- Polyline: multi-point distance
- Spline: smooth multi-point distance (Catmull-Rom interpolated)
- Circle: center and radius
- Angle: line-line intersection angle

The main motivation behind the tool is precision. This is achieved by allowing image magnification changes while measuring. This allows the user to place points precisely using the mouse. Additionally, all measurements can by edited to allow further refinement.

The GUI is reasonably self contained, all code resides in one file: measuretool.m
This file also contains the GUI help, which is available through the GUI itself. See the header of measuretool.m for more info.

The tool has been hosted on the Matlab FileExchange since November 2009, the corresponding website can be found here:
http://www.mathworks.com/matlabcentral/fileexchange/25964-image-measurement-utility. Recently, that site is linked to the GitHub repository, which can be found here: https://github.com/Jann5s/measuretool.

Please let me know (by submitting and issue on GitHub) if you find any bugs or issues, or if you have some nice ideas for improvement.
