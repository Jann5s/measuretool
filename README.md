# measuretool

This is the README accompanying measuretool.m.
measuretool.m is a matlab function that contains a GUI (Graphical User Interface).
Since it is a matlab function it requires matlab, and due to heavy use of the graphics 
features introduced with 2014b, this tool requires at least 2014b.

The tool has been hosted on the Matlab FileExchange since November 2009, 
the corresponding website can be found here:
http://www.mathworks.com/matlabcentral/fileexchange/25964-image-measurement-utility

The current version (2.00) is not yet uploaded to the file exchange, since it is
currently in BETA state, and requires testing before it can be uploaded.

More info on the new matlab graphics
https://www.mathworks.com/products/matlab/matlab-graphics.html

The GUI is reasonably self contained, and all code resides in one file:
measuretool.m
This file also contains the GUI help, which is available through the GUI itself.

Here is a the header of the measuretool.m file:
% A = measuretool, a GUI to aid measuring in images, A is the output
% structure containing all measurement objects for each image
%
% A = measuretool(files), where files is a cellarray of strings of
% filenames, allowing initialization with a predefined set of images
%
% A = measuretool(A), alternatively preload the tool with a previously
% generated data structure containing image paths and measurements
%
% Version 2.00, 2017, Jan Neggers
%
% This tool is available on the Mathworks FileExchange under the
% corresponding BSD license.
% http://www.mathworks.nl/matlabcentral/fileexchange/25964-image-measurement-utility
%
% Quick Help (for more help use the <Help> button in the GUI)
% =============================
%  - Add images to the list using the <Add> button
%  - Calibrate the image pixelsize using the <Calibrate> button
%       - This opens a popup which asks for the real length of the object you will calibrate on
%       - Pressing <OK> in the popup will close the popup
%       - Next, select the start and end point of the calibration object using the mouse
%       - The calibration can be modified later on if so desired using <Edit>
%  - Use the buttons in the <Measure> panel to start measuring
%  - Each measurement can be deleted using <Delete> or modified using <Edit>
%  - Look at the <Status> panel for guidance while using the different tools

