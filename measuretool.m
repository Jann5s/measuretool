function varargout = measuretool(varargin)
% A = measuretool, a GUI to aid measuring in images, A is the output
% structure containing all measurement objects for each image
%
% A = measuretool(files), where files is a cellarray of strings of
% filenames, allowing initialization with a predefined set of images
%
% A = measuretool(A), alternatively preload the tool with a previously
% generated data structure containing image paths and measurements
%
% Version 2.01, 2018, Jan Neggers
%
% This tool is available on the Mathworks FileExchange under the
% corresponding BSD license.
% http://www.mathworks.nl/matlabcentral/fileexchange/25964-image-measurement-utility
%
% Quick Help (for more help use the <Help> button in the GUI)
% =============================
%  - Add images to the list using the <Add> button
%  - Calibrate the image pixelsize using the <Calibrate> button
%       - This opens a popup which asks for the real length of the object
%         you will calibrate on
%       - Pressing <OK> in the popup will close the popup
%       - Next, select the start and end point of the calibration object
%         using the mouse
%       - The calibration can be modified later on using <Edit>
%  - Use the buttons in the <Measure> panel to start measuring
%  - Each measurement can be deleted  or modified using <Delete> or <Edit>
%  - Look at the <Status> panel for guidance while using the different
%    tools






% General Layout of the code
% ------------------------------
% This GUI is build using the concept of sub-functions with shared
% variables (globals). The main function is the GUI, and all other
% functions reside inside. A set of variables that define the state of the
% GUI are used as globals and many functions may write to them,
% occasionally at the same time. This type of programming may be a bit
% dangerous, but for the case at hand it works fine. In the rare case of a
% conflict, the half-finished measuement is just deleted, allowing the new
% measurement to be created.
%
% The code is structured in 4 parts:
% - Definitions of defaults and initiation of global variables
% - Creation of the Interface windows and controls
% - Sub-functions, in 3 categories
%      - Functions related to mouse movements and clicks
%      - Callback functions, i.e. related to control events
%      - Helper functions,
% - End of GUI with output processing
%
% The figure window has three interactive function handles that are
% inportant: 
% - WindowButtonMotionFcn
% - WindowButtonDownFcn
% - WindowButtonUpFcn
% Depending on actions of the user, the handles will point to different
% functions. Typically, there is one function per measurement type to
% handle the live drawing of the object. For the measurements mouse clicks
% are all handles by the addpoints function. However, the Edit/Delete/Copy
% operations have their own click and release functions.

% Option Defaults
% ------------------------------
PlotColors = [8,2];
PlotMarkers = [1,2];
MarkerSize = 14;
TextBoxAlpha = 0.5;
ShowAll = false;
AutoEdit = false;
ZoomSelect = false;
ZoomBox = 250;
Npoints = 200;
MaxPolyline = Inf;
NumberFormat = '%.4g';

% define some colors
colornames = {'white';'black';'red';'green';'blue';'cyan';'magenta';'yellow';'gray'};
color.bg = 0.95*[1, 1, 1];
color.val(1,:) = [1, 1, 1]; %w
color.val(2,:) = [0, 0, 0]; %k
color.val(3,:) = [1, 0, 0]; %r
color.val(4,:) = [0, 1, 0]; %g
color.val(5,:) = [0, 0, 1]; %b
color.val(6,:) = [0, 1, 1]; %c
color.val(7,:) = [1, 0, 1]; %m
color.val(8,:) = [1, 1, 0]; %y
color.val(9,:) = [0.5, 0.5, 0.5]; %gray

% mouse pointers
pointer{1} = 'arrow';  % normal mode
pointer{2} = 'cross';  % point select mode
pointer{3} = 'Circle'; % object select mode

% markers
markers = {'.';'o';'s';'d';'^';'<';'>';'v';'h';'+';'x';'*';'none'};

% linestyle (these could be in the options panel)
LineWidth = [1,2];
linestyles = {'-';'--'};

if ispc
    fixwidthfont = 'FixedWidth';
else
    fixwidthfont = 'Monospaced';
end

% define some special characters (using HTML codes)
um = [char(956),'m']; % micro meter symbol
deg = char(176);      % degree symbol

% list of possible units (using in text objects)
unit_lst = {'km','m','cm','mm','um','nm','-','px','deg.','mi.','ft.','in.'};
% list of possible units (using in text files)
unit_str = {'km','m','cm','mm', um ,'nm','' ,'px', deg  ,'mi.','ft.','in.'};

% default units
unit_default = 7;
unit_val = unit_default;

% default calibration length
calib_length = 1;

% possible image types
imagetypes = {'*.png';'*.jpg';'*.jpeg';'*.gif';'*.tif';'*.tiff';'*.bmp'};
% add all caps versions of  these files
imagetypes = [imagetypes ; upper(imagetypes)];
% convert to an array as a string
imtypstr = sprintf(['%s',repmat(';%s',1,numel(imagetypes)-1)],imagetypes{:});

% Initialize some Globals
% ------------------------------

% data structure
A = [];

% current figure
currentfig = [];
IMG = zeros(10,10);
[imsize(1), imsize(2), imsize(3)] = size(IMG);
userxlim = [1, imsize(2)];
userylim = [1, imsize(1)];

% keep the current path
currentpath = pwd;

% number of clicks in the current procedure
Nclicks = 0;
click_count = 0;
click_data = [];
current_measure_type = 'null';

% globals for selecting and dragging points (Edit/Delete/Copy)
drag_moveall = false;
currentpoint = [];
currentpoint_index = [];
search_points = [];
copy_obj_in_memory = false;

% flag to remember zoom state
zoom_flag = false;

% Determine the GUI window sizes
% ------------------------------

% get the monitor size and the active monitor
Hr = groot;
mon = Hr.MonitorPositions;
Nmon = size(mon,1);
if Nmon > 1
    p0 = Hr.PointerLocation;
    Imon = find(p0(1) >= mon(:,1) & p0(1) < mon(:,1)+mon(:,3) & p0(2) >= mon(:,2) & p0(2) < mon(:,2)+mon(:,4));
    if ~isempty(Imon)
        mon = mon(Imon,:);
    else
        mon = mon(1,:);
    end
end

% determine the fontsize size
if mon(4) <= 800
    fontsize = [7,8,16];
    screenfillfactor = 1;
elseif mon(4) <= 1024
    fontsize = [8,9,18];
    screenfillfactor = 0.95;
elseif mon(4) <= 1280
    fontsize = [10,12,20];
    screenfillfactor = 0.85;
else
    fontsize = [12,14,22];
    screenfillfactor = 0.75;
end

% figure positions
tb_height = screenfillfactor*mon(4);
tb_width = 0.30*tb_height;
iw_width = screenfillfactor*min((mon(3)/mon(4))*tb_height,(mon(3)-tb_width));
iw_x = max(0.5*(mon(3)-tb_width-iw_width),1);
tb_x = min(iw_x+iw_width,mon(3)-tb_width);
tb_y = max(0.5*(mon(4)-tb_height),1);

% toolbar position
pos.tb(1,1) = mon(1)+tb_x;
pos.tb(1,2) = mon(2)+tb_y;
pos.tb(1,3) = tb_width;
pos.tb(1,4) = tb_height;

% image window position
pos.iw(1,1) = mon(1)+iw_x;
pos.iw(1,2) = mon(2)+tb_y;
pos.iw(1,3) = iw_width;
pos.iw(1,4) = tb_height;

% Create the GUI windows
% ------------------------------

% The toolbar figure
Htb = figure('OuterPosition',pos.tb);
Htb.Name = 'Measure Tool';
Htb.NumberTitle = 'off';
Htb.Color = color.bg;
Htb.MenuBar = 'none';
Htb.ToolBar = 'none';
Htb.Tag = 'MT_Toolbar';
Htb.Units = 'Normalized';
Htb.KeyPressFcn = @keyPressFcn;
Htb.KeyReleaseFcn = @keyReleaseFcn;

% The toolbar figure
Hf = figure('OuterPosition',pos.iw);
Hf.Name = 'Measure Tool (Image)';
Hf.NumberTitle = 'off';
Hf.Color = color.bg;
Hf.MenuBar = 'none';
Hf.ToolBar = 'figure';
Hf.Tag = 'MT_Image';
Hf.Units = 'Normalized';

% Calibration figure
Hcal = [];

% setup the figure such that it will allow user control
Hf.WindowButtonMotionFcn = @none_move;
Hf.WindowButtonDownFcn = @null_fun;
Hf.WindowButtonUpFcn = @null_fun;
Hf.KeyPressFcn = @keyPressFcn;
Hf.KeyReleaseFcn = @keyReleaseFcn;
Hf.WindowScrollWheelFcn = @WindowScrollWheelFcn;
Hf.DoubleBuffer = 'on';
Hf.DeleteFcn = @exitGUI;

% Create the image axes
% ----------------------------------
Ha = axes('Position',[0.02,0.02,0.96,0.96],'Parent',Hf);
Hi = imagesc(IMG,'Parent',Ha);
Ha.DataAspectRatio = [1, 1, 1];
Ha.NextPlot = 'Add';
Ha.XColor = 'none';
Ha.YColor = 'none';
Ha.Clipping = 'off';
Ha.Color = 'none';
colormap(Ha,gray);

% prevent the figures from being closed by "close all"
Htb.HandleVisibility = 'Off';
Hf.HandleVisibility = 'Off';

% drag highligh object
Hdrag = plot(NaN,NaN,'or',NaN,NaN,'.r','Parent',Ha,'MarkerSize',MarkerSize+4);

% Temporary handles for half finished measurements
% ----------------------------------
Htmp = []; % temp drawing
Hh = []; % the help window

% Create the GUI panels
% ----------------------------------
x0 = (1/100)*[1 99];
dy = (1/100)*[10,15,10,5]; % save, measure, calib, status
y0 = [cumsum([0.01, dy]), 0.96, 0.99];

Hp(1) = uipanel('Title','Images','Parent',Htb,...
    'Position',[x0(1),y0(5),x0(2)-x0(1),y0(6)-y0(5)]);
Hp(2) = uipanel('Title','Status','Parent',Htb,...
    'Position',[x0(1),y0(4),x0(2)-x0(1),y0(5)-y0(4)]);
Hp(3) = uipanel('Title','Calibrate','Parent',Htb,...
    'Position',[x0(1),y0(3),x0(2)-x0(1),y0(4)-y0(3)]);
Hp(4) = uipanel('Title','Measure','Parent',Htb,...
    'Position',[x0(1),y0(2),x0(2)-x0(1),y0(3)-y0(2)]);
Hp(5) = uipanel('Title','Save','Parent',Htb,...
    'Position',[x0(1),y0(1),x0(2)-x0(1),y0(2)-y0(1)]);
Hp(6) = uipanel('Title','Options','Parent',Htb,...
    'Position',[x0(1),y0(1),x0(2)-x0(1),y0(6)-y0(1)],...
    'Visible','Off');

set(Hp,'BackgroundColor',color.bg,'FontSize',fontsize(1),'Units','normalized');

% Create the GUI buttons
% ----------------------------------

% corner coordinates
Hc = uicontrol('String','',...
    'Style','text',...
    'FontWeight','bold',...
    'HorizontalAlignment','left',...
    'Units','normalized',...
    'Position',[0 0 0.03 0.015],...
    'FontSize',fontsize(1),...
    'Parent',Hf);

% figure title
Ht = uicontrol('String','',...
    'Style','text',...
    'FontWeight','bold',...
    'HorizontalAlignment','center',...
    'Units','normalized',...
    'Position',[0 1-0.015 1 0.015],...
    'FontSize',fontsize(1),...
    'Parent',Hf);

% Status
Hs = uicontrol('String','Status...',...
    'Style','text',...
    'FontWeight','bold',...
    'HorizontalAlignment','left',...
    'Units','normalized',...
    'Position',[0.05 0.05 0.9 0.9],...
    'FontSize',fontsize(2),...
    'Parent',Hp(2));


% Main
x0 = linspace(0.01,0.99,4);
uicontrol('String','Help',...
    'ToolTipString','toggle the documentation window',...
    'Style','pushbutton',...
    'Units','normalized',...
    'FontSize',fontsize(2),...
    'Position',[x0(1),y0(6),x0(2)-x0(1),y0(7)-y0(6)],...
    'Parent',Htb,...
    'call',@help_fun);

uicontrol('String','Options',...
    'ToolTipString','toggle the options panel',...
    'Style','pushbutton',...
    'Units','normalized',...
    'FontSize',fontsize(2),...
    'Position',[x0(2),y0(6),x0(2)-x0(1),y0(7)-y0(6)],...
    'Parent',Htb,...
    'call',@options_button);

uicontrol('String','Reset',...
    'ToolTipString','reset the GUI (Warning: this clears all data)',...
    'Style','pushbutton',...
    'Units','normalized',...
    'FontSize',fontsize(2),...
    'Position',[x0(3),y0(6),x0(2)-x0(1),y0(7)-y0(6)],...
    'Parent',Htb,...
    'call',@reset_fun);

% Image Controls
x0 = linspace(0.01,0.99,4);
y0 = linspace(0.99,0.01,12);
uicontrol('String','Add',...
    'ToolTipString','add images to the list',...
    'Style','pushbutton',...
    'Units','normalized',...
    'FontSize',fontsize(2),...
    'Position',[x0(2),y0(end),x0(2)-x0(1),0.98*(y0(1)-y0(2))],...
    'Parent',Hp(1),...
    'call',{@image_fun,'add'});

uicontrol('String','Remove',...
    'ToolTipString','remove the selected images from the list',...
    'Style','pushbutton',...
    'Units','normalized',...
    'FontSize',fontsize(2),...
    'Position',[x0(3),y0(end),x0(2)-x0(1),0.98*(y0(1)-y0(2))],...
    'Parent',Hp(1),...
    'call',{@image_fun,'del'});

Hb.imlist = uicontrol('String','',...
    'Style','listbox',...
    'Units','normalized',...
    'Value',[],...
    'Max',2,...
    'FontSize',fontsize(2),...
    'Position',[x0(1),y0(end-1),x0(4)-x0(1),y0(1)-y0(end-1)],...
    'Parent',Hp(1),...
    'call',{@image_fun,'select'});

% Calibration
x0 = linspace(0.01,0.99,4);
y0 = linspace(0.99,0.01,3);
dx = 0.98*(x0(2)-x0(1));
dy = 0.95*(y0(1)-y0(2));
uicontrol('String','Length/px',...
    'Style','text',...
    'HorizontalAlignment','left',...
    'Units','normalized',...
    'FontSize',fontsize(2),...
    'Position',[x0(1),y0(2),dx,0.9*dy],...
    'Parent',Hp(3));
Hb.pixelsize = uicontrol('String','-',...
    'Style','text',...
    'HorizontalAlignment','left',...
    'Units','normalized',...
    'FontSize',fontsize(2),...
    'Position',[x0(2),y0(2),0.98*(x0(4)-x0(2)),0.9*dy],...
    'Parent',Hp(3));
uicontrol('String','Calibrate',...
    'ToolTipString','calibrate on the current image (draw a line on the Calibration object)',...
    'Style','pushbutton',...
    'Units','normalized',...
    'FontSize',fontsize(2),...
    'Position',[x0(1),y0(3),dx,dy],...
    'Parent',Hp(3),...
    'call',{@calib_fun,'Calibration'});
uicontrol('String','Apply',...
    'ToolTipString','apply the current Calibration to all selected images',...
    'Style','pushbutton',...
    'Units','normalized',...
    'FontSize',fontsize(2),...
    'Position',[x0(2),y0(3),dx,dy],...
    'Parent',Hp(3),...
    'call',{@calib_fun,'apply'});
uicontrol('String','Clear',...
    'ToolTipString','clear the Calibration for all selected images',...
    'Style','pushbutton',...
    'Units','normalized',...
    'FontSize',fontsize(2),...
    'Position',[x0(3),y0(3),dx,dy],...
    'Parent',Hp(3),...
    'call',{@calib_fun,'clear'});

% Measurement
x0 = linspace(0.01,0.99,4);
dx = 0.98*(x0(2)-x0(1));
y0 = linspace(0.99,0.01,4);
dy = 0.95*(y0(1)-y0(2));
uicontrol('String','Distance (D)',...
    'ToolTipString','measure the Distance between two points',...
    'Style','pushbutton',...
    'Units','normalized',...
    'FontSize',fontsize(2),...
    'Position',[x0(1),y0(2),dx,dy],...
    'Parent',Hp(4),...
    'call',{@measure_fun,'Distance'});
uicontrol('String','Polyline (P)',...
    'ToolTipString','measure the Distance along a serie of points',...
    'Style','pushbutton',...
    'Units','normalized',...
    'FontSize',fontsize(2),...
    'Position',[x0(2),y0(2),dx,dy],...
    'Parent',Hp(4),...
    'call',{@measure_fun,'Polyline'});
uicontrol('String','Circle (O)',...
    'ToolTipString','measure the radius of a Circle (defined by two points)',...
    'Style','pushbutton',...
    'Units','normalized',...
    'FontSize',fontsize(2),...
    'Position',[x0(3),y0(2),dx,dy],...
    'Parent',Hp(4),...
    'call',{@measure_fun,'Circle'});
uicontrol('String','Caliper (C)',...
    'ToolTipString','measure the shortest Distance between a line and a point',...
    'Style','pushbutton',...
    'Units','normalized',...
    'FontSize',fontsize(2),...
    'Position',[x0(1),y0(3),dx,dy],...
    'Parent',Hp(4),...
    'call',{@measure_fun,'Caliper'});
uicontrol('String','Spline (S)',...
    'ToolTipString','measure the Distance along a curved path (Catmull-Rom Spline)',...
    'Style','pushbutton',...
    'Units','normalized',...
    'FontSize',fontsize(2),...
    'Position',[x0(2),y0(3),dx,dy],...
    'Parent',Hp(4),...
    'call',{@measure_fun,'Spline'});
uicontrol('String','Angle (A)',...
    'ToolTipString','measure the Angle between two lines (defined by three points)',...
    'Style','pushbutton',...
    'Units','normalized',...
    'FontSize',fontsize(2),...
    'Position',[x0(3),y0(3),dx,dy],...
    'Parent',Hp(4),...
    'call',{@measure_fun,'Angle'});
uicontrol('String','Edit (E)',...
    'ToolTipString','move a previously defined point',...
    'Style','pushbutton',...
    'Units','normalized',...
    'FontSize',fontsize(2),...
    'Position',[x0(1),y0(4),dx,dy],...
    'Parent',Hp(4),...
    'call',{@measure_fun,'Edit'});
uicontrol('String','Delete (del)',...
    'ToolTipString','delete a measurement',...
    'Style','pushbutton',...
    'Units','normalized',...
    'FontSize',fontsize(2),...
    'Position',[x0(2),y0(4),dx,dy],...
    'Parent',Hp(4),...
    'call',{@measure_fun,'Delete'});
uicontrol('String','Copy (space)',...
    'ToolTipString','copy a measurement',...
    'Style','pushbutton',...
    'Units','normalized',...
    'FontSize',fontsize(2),...
    'Position',[x0(3),y0(4),dx,dy],...
    'Parent',Hp(4),...
    'call',{@measure_fun,'Copy'});

% Save
x0 = linspace(0.01,0.99,4);
dx = 0.98*(x0(2)-x0(1));
y0 = linspace(0.99,0.01,3);
dy = 0.95*(y0(1)-y0(2));
uicontrol('String','Save Project',...
    'ToolTipString','save the current state to a .mat file',...
    'Style','pushbutton',...
    'Units','normalized',...
    'FontSize',fontsize(2),...
    'Position',[x0(1),y0(3),dx,dy],...
    'Parent',Hp(5),...
    'call',{@save_fun,'SaveProject'});
uicontrol('String','Load Project',...
    'ToolTipString','load a previously saved .mat file',...
    'Style','pushbutton',...
    'Units','normalized',...
    'FontSize',fontsize(2),...
    'Position',[x0(1),y0(2),dx,dy],...
    'Parent',Hp(5),...
    'call',{@save_fun,'LoadProject'});
uicontrol('String','Save to PNG',...
    'ToolTipString','save the current view as a PNG',...
    'Style','pushbutton',...
    'Units','normalized',...
    'FontSize',fontsize(2),...
    'Position',[x0(2),y0(3),dx,dy],...
    'Parent',Hp(5),...
    'call',{@save_fun,'SavePNG'});
uicontrol('String','Save to PDF',...
    'ToolTipString','save the current view as a PDF',...
    'Style','pushbutton',...
    'Units','normalized',...
    'FontSize',fontsize(2),...
    'Position',[x0(2),y0(2),dx,dy],...
    'Parent',Hp(5),...
    'call',{@save_fun,'SavePDF'});
uicontrol('String','Save to Text',...
    'ToolTipString','write all data to a formatted text file',...
    'Style','pushbutton',...
    'Units','normalized',...
    'FontSize',fontsize(2),...
    'Position',[x0(3),y0(2),dx,dy],...
    'Parent',Hp(5),...
    'call',{@save_fun,'SaveText'});

% options
x0 = linspace(0.01,0.99,3);
dx = 0.98*(x0(2)-x0(1));
y0 = linspace(0.99,0.01,30);
dy = 0.95*(y0(1)-y0(2));
row = 2;
uicontrol('String','Plot Color 1',...
    'Style','text',...
    'HorizontalAlignment','left',...
    'Units','normalized',...
    'FontSize',fontsize(2),...
    'Position',[x0(1),y0(row),dx,dy],...
    'Parent',Hp(6));
Hb.plotcolor(1) = uicontrol('String',colornames,...
    'ToolTipString','select the foreground plot color',...
    'Style','popupmenu',...
    'Value',PlotColors(1),...
    'Units','normalized',...
    'FontSize',fontsize(2),...
    'Position',[x0(2),y0(row),dx,dy],...
    'call',@options_fun,...
    'Parent',Hp(6));
row = row + 1;
uicontrol('String','Plot Color 2',...
    'Style','text',...
    'HorizontalAlignment','left',...
    'Units','normalized',...
    'FontSize',fontsize(2),...
    'Position',[x0(1),y0(row),dx,dy],...
    'Parent',Hp(6));
Hb.plotcolor(2) = uicontrol('String',colornames,...
    'ToolTipString','select the background plot color',...
    'Style','popupmenu',...
    'Value',PlotColors(2),...
    'Units','normalized',...
    'FontSize',fontsize(2),...
    'Position',[x0(2),y0(row),dx,dy],...
    'call',@options_fun,...
    'Parent',Hp(6));
row = row + 1;
uicontrol('String','Plot Marker 1',...
    'Style','text',...
    'HorizontalAlignment','left',...
    'Units','normalized',...
    'FontSize',fontsize(2),...
    'Position',[x0(1),y0(row),dx,dy],...
    'Parent',Hp(6));
Hb.plotmarker(1) = uicontrol('String',markers,...
    'ToolTipString','select the foreground plot marker',...
    'Style','popupmenu',...
    'Value',PlotMarkers(1),...
    'Units','normalized',...
    'FontSize',fontsize(2),...
    'Position',[x0(2),y0(row),dx,dy],...
    'call',@options_fun,...
    'Parent',Hp(6));
row = row + 1;
uicontrol('String','Plot Marker 2',...
    'Style','text',...
    'HorizontalAlignment','left',...
    'Units','normalized',...
    'FontSize',fontsize(2),...
    'Position',[x0(1),y0(row),dx,dy],...
    'Parent',Hp(6));
Hb.plotmarker(2) = uicontrol('String',markers,...
    'ToolTipString','select the background plot marker',...
    'Style','popupmenu',...
    'Value',PlotMarkers(2),...
    'Units','normalized',...
    'FontSize',fontsize(2),...
    'Position',[x0(2),y0(row),dx,dy],...
    'call',@options_fun,...
    'Parent',Hp(6));
row = row + 1;
uicontrol('String','Marker Size',...
    'Style','text',...
    'HorizontalAlignment','left',...
    'Units','normalized',...
    'FontSize',fontsize(2),...
    'Position',[x0(1),y0(row),dx,dy],...
    'Parent',Hp(6));
Hb.markersize = uicontrol('String',num2str(MarkerSize),...
    'ToolTipString','set the marker size',...
    'Style','Edit',...
    'HorizontalAlignment','center',...
    'Units','normalized',...
    'FontSize',fontsize(2),...
    'Position',[x0(2),y0(row),dx,dy],...
    'call',@options_fun,...
    'Parent',Hp(6));

row = row + 2;
uicontrol('String','Font Size',...
    'Style','text',...
    'HorizontalAlignment','left',...
    'Units','normalized',...
    'FontSize',fontsize(2),...
    'Position',[x0(1),y0(row),dx,dy],...
    'Parent',Hp(6));
Hb.fontsize = uicontrol('String',num2str(fontsize(3)),...
    'ToolTipString','set the font size of the measurement labels',...
    'Style','Edit',...
    'HorizontalAlignment','center',...
    'Units','normalized',...
    'FontSize',fontsize(2),...
    'Position',[x0(2),y0(row),dx,dy],...
    'call',@options_fun,...
    'Parent',Hp(6));
row = row + 1;
uicontrol('String','Text Box Alpha',...
    'Style','text',...
    'HorizontalAlignment','left',...
    'Units','normalized',...
    'FontSize',fontsize(2),...
    'Position',[x0(1),y0(row),dx,dy],...
    'Parent',Hp(6));
Hb.textboxalpha = uicontrol('String',num2str(TextBoxAlpha),...
    'ToolTipString','set the transperancy of the text label background (between 0 and 1)',...
    'Style','Edit',...
    'HorizontalAlignment','center',...
    'Units','normalized',...
    'FontSize',fontsize(2),...
    'Position',[x0(2),y0(row),dx,dy],...
    'call',@options_fun,...
    'Parent',Hp(6));
row = row + 1;
uicontrol('String','Number Formatting',...
    'Style','text',...
    'HorizontalAlignment','left',...
    'Units','normalized',...
    'FontSize',fontsize(2),...
    'Position',[x0(1),y0(row),dx,dy],...
    'Parent',Hp(6));
Hb.NumberFormat = uicontrol('String',NumberFormat,...
    'ToolTipString','Define how number are displayed, e.g. %.2f for two significant digits on floating point form (see sprintf)',...
    'Style','Edit',...
    'HorizontalAlignment','center',...
    'Units','normalized',...
    'FontSize',fontsize(2),...
    'Position',[x0(2),y0(row),dx,dy],...
    'call',@options_fun,...
    'Parent',Hp(6));

row = row + 2;
Hb.autoedit = uicontrol('String','Auto Edit',...
    'ToolTipString','automatically go to edit mode after creating a new measurement',...
    'Style','checkbox',...
    'Value',AutoEdit,...
    'HorizontalAlignment','left',...
    'Units','normalized',...
    'FontSize',fontsize(2),...
    'Position',[x0(1),y0(row),x0(3)-x0(1),dy],...
    'call',@options_fun,...
    'Parent',Hp(6));
row = row + 1;
Hb.zoomselect = uicontrol('String','Zoom Select (Z)',...
    'ToolTipString','zoom the image at the point of interst before defining a measurement point',...
    'Style','checkbox',...
    'Value',ZoomSelect,...
    'HorizontalAlignment','left',...
    'Units','normalized',...
    'FontSize',fontsize(2),...
    'Position',[x0(1),y0(row),x0(3)-x0(1),dy],...
    'call',@options_fun,...
    'Parent',Hp(6));
row = row + 1;
uicontrol('String','Zoom Box Size',...
    'Style','text',...
    'HorizontalAlignment','left',...
    'Units','normalized',...
    'FontSize',fontsize(2),...
    'Position',[x0(1),y0(row),dx,dy],...
    'Parent',Hp(6));
Hb.zoombox = uicontrol('String',num2str(ZoomBox),...
    'ToolTipString','the size of the zoom box in pixels when using Zoom Select',...
    'Style','Edit',...
    'HorizontalAlignment','center',...
    'Units','normalized',...
    'FontSize',fontsize(2),...
    'Position',[x0(2),y0(row),dx,dy],...
    'call',@options_fun,...
    'Parent',Hp(6));
row = row + 1;
Hb.showall = uicontrol('String','Show All',...
    'ToolTipString','show all measurements on each image, instead of only those meaured on the current image',...
    'Style','checkbox',...
    'Value',ShowAll,...
    'HorizontalAlignment','left',...
    'Units','normalized',...
    'FontSize',fontsize(2),...
    'Position',[x0(1),y0(row),x0(3)-x0(1),dy],...
    'call',@options_fun,...
    'Parent',Hp(6));
row = row + 1;
uicontrol('String','Number of points',...
    'Style','text',...
    'HorizontalAlignment','left',...
    'Units','normalized',...
    'FontSize',fontsize(2),...
    'Position',[x0(1),y0(row),dx,dy],...
    'Parent',Hp(6));
Hb.Npoints = uicontrol('String',num2str(Npoints),...
    'ToolTipString','the number of interpolation points to use for smooth lines (only for Spline and Circle)',...
    'Style','Edit',...
    'HorizontalAlignment','center',...
    'Units','normalized',...
    'FontSize',fontsize(2),...
    'Position',[x0(2),y0(row),dx,dy],...
    'call',@options_fun,...
    'Parent',Hp(6));
row = row + 1;
uicontrol('String','PolyLine Max Points',...
    'Style','text',...
    'HorizontalAlignment','left',...
    'Units','normalized',...
    'FontSize',fontsize(2),...
    'Position',[x0(1),y0(row),dx,dy],...
    'Parent',Hp(6));
Hb.MaxPolyline = uicontrol('String',num2str(MaxPolyline),...
    'ToolTipString','the maximum number of points for Polyline and Spline',...
    'Style','Edit',...
    'HorizontalAlignment','center',...
    'Units','normalized',...
    'FontSize',fontsize(2),...
    'Position',[x0(2),y0(row),dx,dy],...
    'call',@options_fun,...
    'Parent',Hp(6));


% Input Processing
% ===========================================================

if nargin == 1
    B = varargin{1};
    if isstruct(B)
        structload_fun(B);
    elseif iscell(B)
        cellstrload_fun(B);
    elseif ischar(B)
        cellstrload_fun({B});
    end
    if ~isempty(A) && isfield(A,'filename')
        currentpath = fileparts(A(1).filename);
    end
end

% Keyboard Mouse
% ===========================================================
    function keyPressFcn(varargin)
        % keyboard presses
        evnt = varargin{2};
        if strcmpi(evnt.Key,'escape')
            % panic button, reset the gui to some sane state
            measure_fun([],[],'null')
            userxlim = [1 imsize(2)];
            userylim = [1 imsize(1)];
            set(Ha,'XLim',userxlim);
            set(Ha,'YLim',userylim);
            set(Hs,'String','...');
            % cancel calibration
            if ishandle(Hcal)
                delete(Hcal)
            end
        elseif strcmpi(evnt.Key,'space')
            measure_fun([],[],'Copy')
        elseif strcmpi(evnt.Key,'d')
            measure_fun([],[],'Distance')
        elseif strcmpi(evnt.Key,'p')
            measure_fun([],[],'Polyline')
        elseif strcmpi(evnt.Key,'o')
            measure_fun([],[],'Circle')
        elseif strcmpi(evnt.Key,'c')
            measure_fun([],[],'Caliper')
        elseif strcmpi(evnt.Key,'s')
            measure_fun([],[],'Spline')
        elseif strcmpi(evnt.Key,'a')
            measure_fun([],[],'Angle')
        elseif strcmpi(evnt.Key,'e')
            measure_fun([],[],'Edit')
        elseif strcmpi(evnt.Key,'z')
            ZoomSelect = ~ZoomSelect;
            set(Hb.zoomselect,'Value',ZoomSelect);
            if ZoomSelect
                Hs.String = 'Zoom Select is activated';
            else
                Hs.String = 'Zoom Select is deactivated';
                if zoom_flag
                    zoom_flag = false;
                    set(Ha,'XLim',userxlim,'YLim',userylim);
                end
            end
        elseif strcmpi(evnt.Key,'Delete')
            measure_fun([],[],'delete')
        elseif strcmpi(evnt.Key,'backspace')
            measure_fun([],[],'Delete')
        elseif strcmpi(evnt.Key,'control')
            drag_moveall = true;
        elseif strcmpi(evnt.Key,'downarrow')
            val = currentfig;
            Nval = numel(Hb.imlist.String);
            val = min(val+1,Nval);
            set(Hb.imlist,'Value',val);
            image_fun([],[],'select')
        elseif strcmpi(evnt.Key,'uparrow')
            val = currentfig;
            val = max(val-1,1);
            set(Hb.imlist,'Value',val);
            image_fun([],[],'select')
        end
    end

    function keyReleaseFcn(varargin)
        % when releasing a key
        evnt = varargin{2};
        if strcmpi(evnt.Key,'control')
            drag_moveall = false;
        end
    end


% Measurement Controls
% ===========================================================

% none ------------------------
    function none_move(varargin)
        % place holder to do nothing, with the mouse moving
        p = get(Ha,'CurrentPoint');
        str = sprintf('%d,%d',round(p(1,1:2)));
        set(Hc,'String',str)
    end

    function null_fun(varargin)
        % do nothing function (used when clicking and no measurement is
        % active)
    end

% drag ------------------------
    function drag_move(varargin)
        % dragging a point from a to b
        p = get(Ha,'CurrentPoint');
        str = sprintf('%d,%d',round(p(1,1:2)));
        set(Hc,'String',str)
        
        if isempty(currentpoint_index)
            return
        end
        
        % move a point
        i = currentpoint_index(1);
        j = currentpoint_index(2);
        I = currentpoint_index(3);
        
        if drag_moveall
            A(i).obj(j).points(:,1) = A(i).obj(j).points(:,1) + (p(1,1)-A(i).obj(j).points(I,1));
            A(i).obj(j).points(:,2) = A(i).obj(j).points(:,2) + (p(1,2)-A(i).obj(j).points(I,2));
        else
            A(i).obj(j).points(I,:) = p(1,1:2);
        end
        update_measurement(i,j);
        set(Hdrag,'XData',p(1,1),'YData',p(1,2));
    end

    function drag_buttondown(varargin)
        % starting a drag operation
        p = get(Ha,'CurrentPoint');
        
        % mouse click type
        m_type = get(varargin{1},'selectionType');
        
        if strcmp(m_type,'open')
            % double click, exit drag mode
            measure_fun([],[],'null');
            Hs.String = 'Exited Edit mode, ';
            return
        end
        
        if isempty(currentpoint)
            return
        end
        
        xi = currentpoint(1);
        yi = currentpoint(2);
        i = currentpoint(3);
        j = currentpoint(4);
        x = A(i).obj(j).points(:,1);
        y = A(i).obj(j).points(:,2);
        I = find( abs(x-xi)<1e-6 & abs(y-yi)<1e-6 );
        if isempty(I)
            return
        end
        
        % not currently dragging
        if strcmp(m_type, 'normal')
            % select a point
            currentpoint_index = [i,j,I(1)];
            drag_moveall = false;
            set(Hf,'WindowButtonMotionFcn',@drag_move)
        elseif strcmp(m_type, 'alt')
            % select a point
            currentpoint_index = [i,j,I(1)];
            drag_moveall = true;
            set(Hf,'WindowButtonMotionFcn',@drag_move)
        end
    end

    function drag_buttonup(varargin)
        % finishing a drag operation
        set(Hf,'WindowButtonMotionFcn',@point_search)
    end

% Delete ------------------------
    function delete_buttondown(varargin)
        % delete the currently selected object
        p = get(Ha,'CurrentPoint');
        
        % mouse click type
        m_type = get(varargin{1}, 'selectionType');
        
        if strcmp(m_type,'open')
            % double click, exit delete mode
            measure_fun([],[],'null');
            Hs.String = 'Exited Delete mode, ';
            return
        end
        
        if isempty(currentpoint)
            return
        end
        
        i = currentpoint(3);
        j = currentpoint(4);
        not_j = setdiff(1:numel(A(i).obj),j);
        
        % delete the plot object
        delete(A(i).obj(j).hdl);
        % delete the measurement
        A(i).obj = A(i).obj(not_j);
        
        % the mouse is no longer hovering over a control point
        currentpoint = [];
        set(Hf,'Pointer',pointer{2});
        set(Hdrag,'XData',NaN,'YData',NaN);
        
        % update the list of search points
        if ShowAll
            selection = 1:numel(A);
        else
            selection = Hb.imlist.Value;
        end
        search_points_update(selection)
    end

% Copy ------------------------
    function copy_move(varargin)
        % move the object that is currently in copy memory
        p = get(Ha,'CurrentPoint');
        str = sprintf('%d,%d',round(p(1,1:2)));
        set(Hc,'String',str)
        
        if isempty(copy_obj_in_memory)
            return
        end
        
        % move a point
        x = copy_obj_in_memory.points(:,1);
        y = copy_obj_in_memory.points(:,2);
        ux = -x(1) + p(1,1);
        uy = -y(1) + p(1,2);
        
        for k = 1:4
            xp = copy_obj_in_memory.hdl(k).XData;
            yp = copy_obj_in_memory.hdl(k).YData;
            Htmp(k).XData = xp + ux;
            Htmp(k).YData = yp + uy;
        end
        Htmp(5).Position = copy_obj_in_memory.hdl(5).Position + [ux, uy, 0];
        set(Hdrag,'XData',p(1,1),'YData',p(1,2));
    end

    function copy_buttondown(varargin)
        % start a copy action, or place a copy object
        p = get(Ha,'CurrentPoint');
        
        % mouse click type
        m_type = get(varargin{1}, 'selectionType');
        
        if strcmp(m_type,'open')
            % double click or right click, exit delete mode
            measure_fun([],[],'null');
            Hs.String = 'Exited Copy mode, ';
            return
        elseif strcmp(m_type,'alt')
            if ~isempty(copy_obj_in_memory)
                copy_obj_in_memory = [];
                set(Hf,'WindowButtonMotionFcn',@point_search)
                set(Hs,'String','Copy: select an object to Copy');
            end
        end
        
        if isempty(currentpoint)
            return
        end
        
        i = currentpoint(3);
        j = currentpoint(4);
        if isempty(copy_obj_in_memory)
            % copy an object
            delete(Htmp)
            for k = 1:5
                Htmp(k) = copyobj(A(i).obj(j).hdl(k),Ha);
            end
            copy_obj_in_memory = A(i).obj(j);
            if strcmpi(copy_obj_in_memory.type,'Calibration')
                % copy calibration objects as distance
                copy_obj_in_memory.type = 'Distance';
            end
            set(Hf,'WindowButtonMotionFcn',@copy_move)
            set(Hs,'String','Copy: place the selected object');
        else
            % place a selected object
            x = copy_obj_in_memory.points(:,1);
            y = copy_obj_in_memory.points(:,2);
            x = x - x(1) + p(1,1);
            y = y - y(1) + p(1,2);
            
            % store the measurement
            j = numel(A(currentfig).obj)+1;
            A(currentfig).obj(j).type = copy_obj_in_memory.type;
            for k = 1:5
                A(currentfig).obj(j).hdl(k)  = copyobj(Htmp(k),Ha);
            end
            A(currentfig).obj(j).points = [x(:), y(:)];
            
            copy_obj_in_memory = [];
            update_measurement(currentfig,j);
            set(Hf,'WindowButtonMotionFcn',@point_search)
            set(Hs,'String','Copy: select an object to Copy');
        end
    end

% Search for a point to interact with (Drag, Delete, Copy)
% -----------------------------
    function point_search(varargin)
        % Select a poit for later action
        p = get(Ha,'CurrentPoint');
        str = sprintf('%d,%d',round(p(1,1:2)));
        set(Hc,'String',str)
        
        % find a nearby point
        if isempty(search_points)
            return
        end
        x = search_points(:,1);
        y = search_points(:,2);
        
        % selection Distance
        R = 0.05*min(diff(Ha.XLim),diff(Ha.YLim));
        
        D = hypot(x-p(1,1),y-p(1,2));
        if any(D <= R)
            % the mouse is hovering over a control point
            set(Hf,'Pointer',pointer{3});
            
            % find out which control point
            I = find(D <= R);
            if numel(I) > 1
                [D, I] = min(D);
            end
            currentpoint = search_points(I,:);
            set(Hdrag,'XData',x(I),'YData',y(I));
        else
            % the mouse is not hovering over a control point
            currentpoint = [];
            set(Hf,'Pointer',pointer{2});
            set(Hdrag,'XData',NaN,'YData',NaN);
        end
    end

% update the search points
% -----------------------------
    function search_points_update(selection)
        % list of possible points
        x = []; y = []; i = []; j = [];
        for ifig = selection
            Nobj = numel(A(ifig).obj);
            for k = 1:Nobj
                Np = size(A(ifig).obj(k).points,1);
                x = [x; A(ifig).obj(k).points(:,1)];
                y = [y; A(ifig).obj(k).points(:,2)];
                i = [i; ifig*ones(Np,1)];
                j = [j; k*ones(Np,1)];
            end
        end
        search_points = [x,y,i,j,];
    end


% calib ------------------------
    function calib_move(varargin)
        % mouse movements during the definition of the calibration object
        p = get(Ha,'CurrentPoint');
        str = sprintf('%d,%d',round(p(1,1:2)));
        set(Hc,'String',str)
        
        if Nclicks ~= 2
            % something is wrong, abort
            delete(Htmp)
            measure_fun([],[],'null');
            set(Hs,'String','Measurement aborted');
            return
        end
        
        if click_count == 0
            % nothing is selected yet
            x = p(1,1);
            y = p(1,2);
            set(Htmp(1:4),'XData',x,'YData',y);
            set(Htmp(5),'Position',[x, y, 0],'String','','Rotation',0);
        elseif click_count < Nclicks
            % one point is done, determining the other
            x = [click_data(:,1) ; p(1,1)];
            y = [click_data(:,2) ; p(1,2)];
            a = (180/pi)*atan2(diff(y),diff(x));
            a = textangle(a);
            r = hypot(diff(x),diff(y));
            str = sprintf([NumberFormat ' px'],r);
            set(Htmp(1:4),'XData',x,'YData',y);
            set(Htmp(5),'Position',[mean(x), mean(y), 0],'Rotation',-a,'String',str);
        end
    end

% Distance ------------------------
    function distance_move(varargin)
        % mouse movements during the definition of the distance measure object
        p = get(Ha,'CurrentPoint');
        str = sprintf('%d,%d',round(p(1,1:2)));
        set(Hc,'String',str)
        
        if Nclicks ~= 2
            % something is wrong, abort
            delete(Htmp)
            measure_fun([],[],'null');
            set(Hs,'String','Measurement aborted');
            return
        end
        
        i = currentfig;
        pixelsize = A(i).pixelsize;
        unit = A(i).unit;
        if isempty(pixelsize)
            pixelsize = [1, 1, 1];
            unit = 'px';
        end
        
        if click_count == 0
            % nothing is selected yet
            x = p(1,1);
            y = p(1,2);
            set(Htmp(1:4),'XData',x,'YData',y);
            set(Htmp(5),'Position',[x, y, 0],'String','','Rotation',0);
        elseif click_count < Nclicks
            % one point is done, determining the other
            x = [click_data(:,1) ; p(1,1)];
            y = [click_data(:,2) ; p(1,2)];
            a = (180/pi)*atan2(diff(y),diff(x));
            a = textangle(a);
            r = hypot(diff(x),diff(y));
            str = sprintf([NumberFormat ' %s'],r.*pixelsize(1),unit);
            set(Htmp(1:4),'XData',x,'YData',y);
            set(Htmp(5),'Position',[mean(x), mean(y), 0],'Rotation',-a,'String',str);
        end
    end

% Circle ------------------------
    function circle_move(varargin)
        % mouse movements during the definition of the circle measure object
        p = get(Ha,'CurrentPoint');
        str = sprintf('%d,%d',round(p(1,1:2)));
        set(Hc,'String',str)
        
        if Nclicks ~= 2
            % something is wrong, abort
            delete(Htmp)
            measure_fun([],[],'null');
            set(Hs,'String','Measurement aborted');
            return
        end
        
        i = currentfig;
        pixelsize = A(i).pixelsize;
        unit = A(i).unit;
        if isempty(pixelsize)
            pixelsize = [1, 1, 1];
            unit = 'px';
        end
        
        if click_count == 0
            % nothing is selected yet
            x = p(1,1);
            y = p(1,2);
            set(Htmp(1:4),'XData',x,'YData',y);
            set(Htmp(5),'Position',[x, y, 0],'String','','Rotation',0);
        elseif (click_count == 1)
            % one point is done, determining the last
            x = [click_data(:,1) ; p(1,1)];
            y = [click_data(:,2) ; p(1,2)];
            a = (180/pi)*atan2(diff(y),diff(x));
            a = textangle(a);
            r = hypot(diff(x),diff(y));
            theta = linspace(0,2*pi,Npoints);
            xc = x(1) + r.*cos(theta(:));
            yc = y(1) + r.*sin(theta(:));
            str = sprintf([NumberFormat ' %s'],r.*pixelsize(1),unit);
            set(Htmp(1:2),'XData',x,'YData',y);
            set(Htmp(3:4),'XData',xc,'YData',yc);
            set(Htmp(5),'Position',[mean(x), mean(y), 0],'Rotation',-a,'String',str);
        end
    end

% Caliper ------------------------
    function caliper_move(varargin)
        % mouse movements during the definition of the caliper measure object
        p = get(Ha,'CurrentPoint');
        str = sprintf('%d,%d',round(p(1,1:2)));
        set(Hc,'String',str)
        
        if Nclicks ~= 3
            % something is wrong, abort
            delete(Htmp)
            measure_fun([],[],'null');
            set(Hs,'String','Measurement aborted');
            return
        end
        
        i = currentfig;
        pixelsize = A(i).pixelsize;
        unit = A(i).unit;
        if isempty(pixelsize)
            pixelsize = [1, 1, 1];
            unit = 'px';
        end
        
        if click_count == 0
            % nothing is selected yet
            x = p(1,1);
            y = p(1,2);
            set(Htmp(1:4),'XData',x,'YData',y);
            set(Htmp(5),'Position',[x, y, 0],'String','','Rotation',0);
        elseif click_count == 1
            % one point is done, determining the next
            x = [click_data(:,1) ; p(1,1)];
            y = [click_data(:,2) ; p(1,2)];
            set(Htmp(1:4),'XData',x,'YData',y);
            set(Htmp(5),'Position',[x(1), y(1), 0],'String','','Rotation',0);
        elseif click_count == 2
            % two points are done, determining the last
            x = [click_data(:,1) ; p(1,1)];
            y = [click_data(:,2) ; p(1,2)];
            [x, y, D] = Caliper(x,y);
            a = (180/pi)*atan2(y(4)-y(3),x(4)-x(3));
            a = textangle(a);
            str = sprintf([NumberFormat ' %s'],abs(D).*pixelsize(1),unit);
            set(Htmp(1:4),'XData',[x(1);x(2);NaN;x(3);x(4)],'YData',[y(1);y(2);NaN;y(3);y(4)]);
            set(Htmp(5),'Position',[mean(x(3:4)), mean(y(3:4)), 0],'Rotation',-a,'String',str);
        end
    end

% Angle ------------------------
    function angle_move(varargin)
        % mouse movements during the definition of the angle measure object
        p = get(Ha,'CurrentPoint');
        str = sprintf('%d,%d',round(p(1,1:2)));
        set(Hc,'String',str)
        
        if Nclicks ~= 3
            % something is wrong, abort
            delete(Htmp)
            measure_fun([],[],'null');
            set(Hs,'String','Measurement aborted');
            return
        end
        
        i = currentfig;
        if click_count == 0
            % nothing is selected yet
            x = p(1,1);
            y = p(1,2);
            set(Htmp(1:4),'XData',x,'YData',y);
            set(Htmp(5),'Position',[x(1), y(1), 0],'String','','Rotation',0);
        elseif click_count == 1
            % one point is done, determining the second
            x = [click_data(:,1) ; p(1,1)];
            y = [click_data(:,2) ; p(1,2)];
            set(Htmp(1:4),'XData',x,'YData',y);
            set(Htmp(5),'Position',[x(1), y(1), 0],'String','','Rotation',0);
        elseif click_count == 2
            % two points are done, determining the last
            x = [click_data(:,1) ; p(1,1)];
            y = [click_data(:,2) ; p(1,2)];
            a1 = atan2(y(1)-y(2),x(1)-x(2));
            a2 = atan2(y(3)-y(2),x(3)-x(2));
            da = a2-a1;
            if da > pi
                da = da - 2*pi;
            elseif da < -pi
                da = da + 2*pi;
            end
            a2 = a1 + da;
            
            r1 = hypot(x(1)-x(2),y(1)-y(2));
            r2 = hypot(x(3)-x(2),y(3)-y(2));
            r = min(r1,r2);
            th = linspace(a1,a2,41);
            xc = x(2) + r.*cos(th);
            yc = y(2) + r.*sin(th);
            
            str = sprintf([NumberFormat ' %s'],(180/pi)*abs(da),deg);
            a = (180/pi)*0.5*(a1+a2) + 90;
            a = textangle(a);
            set(Htmp(1:2),'XData',x,'YData',y);
            set(Htmp(3:4),'XData',xc,'YData',yc);
            set(Htmp(5),'Position',[xc(21), yc(21), 0],'Rotation',-a,'String',str);
        end
    end

% Polyline ------------------------
    function polyline_move(varargin)
        % mouse movements during the definition of the polyline measure object
        p = get(Ha,'CurrentPoint');
        str = sprintf('%d,%d',round(p(1,1:2)));
        set(Hc,'String',str)
        
        i = currentfig;
        pixelsize = A(i).pixelsize;
        unit = A(i).unit;
        if isempty(pixelsize)
            pixelsize = [1, 1, 1];
            unit = 'px';
        end
        
        if click_count == 0
            % nothing is selected yet
            x = p(1,1);
            y = p(1,2);
            set(Htmp(1:4),'XData',x,'YData',y);
            set(Htmp(5),'Position',[x(1), y(1), 0],'String','','Rotation',0);
        elseif click_count < Nclicks
            % one point is done, determining the other
            x = [click_data(:,1) ; p(1,1)];
            y = [click_data(:,2) ; p(1,2)];
            a = (180/pi)*atan2(y(2)-y(1),x(2)-x(1));
            a = textangle(a);
            r = sum(hypot(diff(x),diff(y)));
            str = sprintf([NumberFormat ' %s'],r.*pixelsize(1),unit);
            set(Htmp(1:4),'XData',x,'YData',y);
            set(Htmp(5),'Position',[mean(x([1,2])), mean(y([1,2])), 0],'Rotation',-a,'String',str);
        end
    end

% Polyline ------------------------
    function spline_move(varargin)
        % mouse movements during the definition of the spline measure object
        p = get(Ha,'CurrentPoint');
        str = sprintf('%d,%d',round(p(1,1:2)));
        set(Hc,'String',str)
        
        i = currentfig;
        pixelsize = A(i).pixelsize;
        unit = A(i).unit;
        if isempty(pixelsize)
            pixelsize = [1, 1, 1];
            unit = 'px';
        end
        
        if click_count == 0
            % nothing is selected yet
            x = p(1,1);
            y = p(1,2);
            set(Htmp(1:2),'XData',x,'YData',y);
            set(Htmp(5),'Position',[x(1), y(1), 0],'String','','Rotation',0);
        elseif click_count < Nclicks
            % one point is done, determining the other
            x = [click_data(:,1) ; p(1,1)];
            y = [click_data(:,2) ; p(1,2)];
            
            if click_count > 2
                phi = buildshapefun([x(:),y(:)]);
                Np = size(phi,1);
                Ip = floor(Np/2)+[0, 1];
                xc = phi*x(:);
                yc = phi*y(:);
            else
                xc = x;
                yc = y;
                Ip = [1, 2];
            end
            a = (180/pi)*atan2(diff(yc(Ip)),diff(xc(Ip)));
            a = textangle(a);
            r = sum(hypot(diff(x),diff(y)));
            str = sprintf([NumberFormat ' %s'],r.*pixelsize(1),unit);
            set(Htmp(1:2),'XData',x,'YData',y);
            set(Htmp(3:4),'XData',xc,'YData',yc);
            set(Htmp(5),'Position',[mean(xc(Ip)), mean(yc(Ip)), 0],'Rotation',-a,'String',str);
        end
    end

% clicking during a measurement adds a point or removes a points
% --------------------------------------------
    function addpoint(varargin)
        % runs on mouse clicks while defining a measurement object
        p = get(Ha,'CurrentPoint');
        
        % mouse click type
        m_type = get(varargin{1},'selectionType');
        
        if ismember(current_measure_type,{'Polyline','Spline'})
            str = '(use double click to finish)';
        else
            str = '';
        end
        
        if strcmp(m_type,'open')
            % double click, last point in Polyline or Spline
            Nclicks = click_count;
        elseif strcmp(m_type, 'normal')
            % add the current point
            if ZoomSelect && ~zoom_flag
                userxlim = get(Ha,'XLim');
                userylim = get(Ha,'YLim');
                % zoom local to the cursor
                a = (p(1,1) - userxlim(1))./diff(userxlim);
                xlim(1) = p(1,1) - a*ZoomBox;
                xlim(2) = ZoomBox + xlim(1);                
                b = (p(1,2) - userylim(1))./diff(userylim);
                ylim(1) = p(1,2) - b*ZoomBox;
                ylim(2) = ZoomBox + ylim(1);
                set(Ha,'XLim',xlim,'YLim',ylim);
                zoom_flag = true;
                return
            elseif  ZoomSelect && zoom_flag
                zoom_flag = false;
                set(Ha,'XLim',userxlim,'YLim',userylim);
            end
            % add the current point
            click_data = [click_data ; p(1,1:2)];
            click_count = click_count + 1;
            Hs.String = sprintf('%s (%d/%d): select the next point %s',current_measure_type,click_count,Nclicks,str);
        elseif strcmp(m_type, 'alt') && (click_count > 0)
            if  ZoomSelect && zoom_flag
                zoom_flag = false;
                set(Ha,'XLim',userxlim,'YLim',userylim);
            end
            % remove a point
            click_data = click_data(1:end-1,:);
            click_count = click_count - 1;
            Hs.String = sprintf('%s (%d/%d): select the next point %s',current_measure_type,click_count,Nclicks,str);
        end        
        
        % Last click is detected, this finalized the measurement
        if (click_count > 0) && (click_count == Nclicks)
            i = currentfig;
            Hs.String = sprintf('%s: measurement done',current_measure_type);
            
            if any(strcmpi(current_measure_type,{'null';'Edit';'Delete';'Copy'}))
                return
            end
            
            % store the measurement
            if isfield(A,'obj')
                j = numel(A(i).obj)+1;
            else
                j = 1;
            end
            A(i).obj(j).type = current_measure_type;
            for k = 1:5
                A(i).obj(j).hdl(k)  = copyobj(Htmp(k),Ha);
            end
            delete(Htmp);
            A(i).obj(j).points = click_data;
            
            % calibration, there is more to be done
            if strcmpi(current_measure_type,'Calibration')
                current_measure_type = 'null';
                % delete older calibration objects (of this image)
                list = find(arrayfun(@(x) strcmpi(x.type,'Calibration'),A(i).obj(:)));
                if ~isempty(list)
                    list = setdiff(list,j);
                    notlist = setdiff(1:numel(A(i).obj),list);
                    j = find(notlist==j);
                    
                    % delete the plot object
                    delete([A(i).obj(list).hdl]);
                    % delete the measurement
                    A(i).obj = A(i).obj(notlist);
                end
                
                % list of images to apply calibration to
                list = find(arrayfun(@(x) x.cal==0,A(:)).');
                combined = union(Hb.imlist.Value,list);
                
                % apply the calibration
                r = hypot(diff(click_data(1:2,1)),diff(click_data(1:2,2)));
                length = calib_length;
                unit = unit_str{unit_val};
                pixelsize = [length./r, length, r];
                A(i).obj(j).val_px = r;
                for k = combined
                    A(k).cal = i;
                    A(k).pixelsize = pixelsize;
                    A(k).unit = unit;
                    update_obj(A(k).obj);
                end
            end
            update_measurement(i,j);
            
            if AutoEdit
                measure_fun([],[],'Edit');
            else
                measure_fun([],[],current_measure_type);
            end
        end
    end

% Update a Measurement
% ===========================================================
    function update_measurement(i,j)
        % function to recompute the value of a measurement and reposition
        % the text box. Typically called during the ..._move functions
        % defined above.
        Ni = numel(A);
        if i > Ni
            return
        end
        Nm = numel(A(i).obj);
        if j > Nm
            return
        end
        
        obj = A(i).obj(j);
        if ~isfield(obj,'type')
            return
        end
        type = obj.type;
        hdl = obj.hdl;
        
        pixelsize = A(i).pixelsize;
        unit = A(i).unit;
        if isempty(pixelsize)
            pixelsize = [1, 1, 1];
            unit = 'px';
        end
        
        % update the list of search points
        if ShowAll
            selection = 1:numel(A);
        else
            selection = Hb.imlist.Value;
        end
        search_points_update(selection)
        
        % clear the temporary measurement (if any)
        delete(Htmp);
        
        x = obj.points(:,1);
        y = obj.points(:,2);
        if strcmpi(type,'Calibration')
            a = (180/pi)*atan2(diff(y),diff(x));
            a = textangle(a);
            r = hypot(diff(x),diff(y));
            A(i).obj(j).val_px = r;
            str = sprintf([NumberFormat ' px'],r);
            set(hdl(1:4),'XData',x,'YData',y);
            set(hdl(5),'Position',[mean(x), mean(y), 0],'Rotation',-a,'String',str);
            c = A(i).cal;
            length = A(c).pixelsize(2);
            unit = A(c).unit;
            pixelsize = [length./r, length, r];
            list = find(arrayfun(@(x) x.cal==c,A(:)).');
            for k = list
                A(k).pixelsize = pixelsize;
                A(k).unit = unit;
                A(k).cal = c;
                update_obj(A(k).obj);
            end
            % update the text box in the toolbar
            str = sprintf([NumberFormat ' %s'],pixelsize(1),unit);
            set(Hb.pixelsize,'String',str);
            % update the title
            if A(i).cal == 0
                set(Ht,'String',sprintf('%d, %s (not calibrated)',currentfig,Hb.imlist.String{currentfig}));
            elseif A(i).cal == i
                set(Ht,'String',sprintf('%d, %s (calibrated, px = %s)',currentfig,Hb.imlist.String{currentfig},str));
            else
                set(Ht,'String',sprintf('%d, %s (calibration from %d, px = %s)',currentfig,Hb.imlist.String{currentfig},A(i).cal,str));
            end
        elseif strcmpi(type,'Distance')
            a = (180/pi)*atan2(diff(y),diff(x));
            a = textangle(a);
            r = hypot(diff(x),diff(y));
            A(i).obj(j).val_px = r;
            str = sprintf([NumberFormat ' %s'],r.*pixelsize(1),unit);
            set(hdl(1:4),'XData',x,'YData',y);
            set(hdl(5),'Position',[mean(x), mean(y), 0],'Rotation',-a,'String',str);
        elseif strcmpi(type,'Circle')
            a = (180/pi)*atan2(diff(y),diff(x));
            r = hypot(diff(x),diff(y));
            a = textangle(a);
            A(i).obj(j).val_px = r;
            theta = linspace(0,2*pi,Npoints);
            xc = x(1) + r.*cos(theta(:));
            yc = y(1) + r.*sin(theta(:));
            str = sprintf([NumberFormat ' %s'],r.*pixelsize(1),unit);
            set(hdl(1:2),'XData',x,'YData',y);
            set(hdl(3:4),'XData',xc,'YData',yc);
            set(hdl(5),'Position',[mean(x), mean(y), 0],'Rotation',-a,'String',str);
        elseif strcmpi(type,'Caliper')
            [x, y, D] = Caliper(x,y);
            a = (180/pi)*atan2(y(4)-y(3),x(4)-x(3));
            a = textangle(a);
            A(i).obj(j).val_px = abs(D);
            str = sprintf([NumberFormat ' %s'],A(i).obj(j).val_px*pixelsize(1),unit);
            set(hdl(1:4),'XData',[x(1);x(2);NaN;x(3);x(4)],'YData',[y(1);y(2);NaN;y(3);y(4)]);
            set(hdl(5),'Position',[mean(x(3:4)), mean(y(3:4)), 0],'Rotation',-a,'String',str);
        elseif strcmpi(type,'Angle')
            a1 = atan2(y(1)-y(2),x(1)-x(2));
            a2 = atan2(y(3)-y(2),x(3)-x(2));
            da = a2-a1;
            if da > pi
                da = da - 2*pi;
            elseif da < -pi
                da = da + 2*pi;
            end
            a2 = a1 + da;
            A(i).obj(j).val_px = abs(da);
            r1 = hypot(x(1)-x(2),y(1)-y(2));
            r2 = hypot(x(3)-x(2),y(3)-y(2));
            r = min(r1,r2);
            th = linspace(a1,a2,41);
            xc = x(2) + r.*cos(th);
            yc = y(2) + r.*sin(th);
            str = sprintf([NumberFormat ' %s'],(180/pi)*abs(da),deg);
            a = (180/pi)*0.5*(a1+a2) + 90;
            a = textangle(a);
            set(hdl(1:2),'XData',x,'YData',y);
            set(hdl(3:4),'XData',xc,'YData',yc);
            set(hdl(5),'Position',[xc(21), yc(21), 0],'Rotation',-a,'String',str);
        elseif strcmpi(type,'Polyline')
            if numel(x) > 1
                a = (180/pi)*atan2(y(2)-y(1),x(2)-x(1));
                a = textangle(a);
                r = sum(hypot(diff(x),diff(y)));
                xa = mean(x(1:2));
                ya = mean(y(1:2));
                str = sprintf([NumberFormat ' %s'],r.*pixelsize(1),unit);
            else
                a = 0;
                r = 0;
                xa = x;
                ya = y;
                str = '';
            end
            A(i).obj(j).val_px = r ;
            set(hdl(1:4),'XData',x,'YData',y);
            set(hdl(5),'Position',[xa, ya, 0],'Rotation',-a,'String',str);
        elseif strcmpi(type,'Spline')
            if numel(x) > 2
                phi = buildshapefun([x(:),y(:)]);
                Np = size(phi,1);
                Ip = [floor(Np/2), floor(Np/2)+1];
                xc = phi*x(:);
                yc = phi*y(:);
            else
                xc = x;
                yc = y;
                Ip = [1, 2];
            end
            a = (180/pi)*atan2(diff(yc(Ip)),diff(xc(Ip)));
            a = textangle(a);
            r = sum(hypot(diff(x),diff(y)));
            A(i).obj(j).val_px = r ;
            str = sprintf([NumberFormat ' %s'],r.*pixelsize(1),unit);
            set(hdl(1:2),'XData',x,'YData',y);
            set(hdl(3:4),'XData',xc,'YData',yc);
            set(hdl(5),'Position',[mean(xc(Ip)), mean(yc(Ip)), 0],'Rotation',-a,'String',str);
        end
    end


% Button Callbacks
% ===========================================================

% ---------------------------------------------
    function image_fun(varargin)
        % Buttons in the image panel
        
        type = varargin{3};
        if strcmpi(type,'select')
            % called upon events in the image listbox
            selection = Hb.imlist.Value;
            if numel(selection) == 1
                currentfig = selection(1);
                update_figure;
            end
        elseif strcmpi(type,'add')
            % called upon pressing the Add button
            
            % popup, select files
            [filename, filepath] = uigetfile({imtypstr,'All Image Files';'*.*','All Files' },'Select an Image',currentpath,'MultiSelect','on');
            if ~iscell(filename)
                filename = {filename};
            end
            % if cancel
            if filename{1} == 0
                set(Hs,'string','Add: no file selected')
                return
            end
            % remember the current path
            currentpath = filepath;
            for k = 1:numel(filename)
                A(end+1).filename = fullfile(filepath,filename{k});
                Hb.imlist.String{end+1} = filename{k};
                
                pixelsize = [];
                unit = '';
                c = 0;
                if ~isempty(currentfig) && (A(currentfig).cal ~= 0)
                    % load the previous calibration
                    c = A(currentfig).cal;
                    pixelsize = A(c).pixelsize;
                    unit = A(c).unit;
                end
                % Cascade calibration
                A(end).cal = c;
                A(end).pixelsize = pixelsize;
                A(end).unit = unit;
                % intialize the measurement object structure
                A(end).obj = [];
            end
            if k == 1
                set(Hs,'string','Add: 1 file added');
            else
                set(Hs,'string',sprintf('Add: %d files added',k));
            end
            if numel(A) == numel(filename)
                Hb.imlist.Value = 1;
                image_fun([],[],'select')
            end
        elseif strcmpi(type,'del')
            % called upon pressing the Del button
            
            % remove files from the list (and Delete measurements)
            selected = Hb.imlist.Value;
            if ~isempty(selected)
                % clean any existing plot objects
                for k = selected
                    if ~isfield(A,'obj')
                        continue
                    end
                    delete(A(k).obj(:).hdl);
                end
                Nim = numel(A);
                notselected = setdiff(1:Nim,selected);
                A = A(notselected);
                Hb.imlist.String = Hb.imlist.String(notselected);
                Hb.imlist.Value = [];
                currentfig = [];
                if numel(selected) == 1
                    set(Hs,'string','Remove: 1 file removed from the list');
                else
                    set(Hs,'string',sprintf('Remove: %d files removed from the list',numel(selected)));
                end
            end
        end
    end

% ---------------------------------------------
    function calib_fun(varargin)
        % one of three Calibration buttons is pressed
        if isempty(A)
            set(Hs,'String','No image defined, aborting calibration')
            return
        end
        
        % clear some globals
        reset_globals;
        
        type = varargin{3};
        if strcmpi(type,'Calibration')
            
            % bring figure to the front
            figure(Hf);
            drawnow
            
            % disable any active measurement
            measure_fun([],[],'null')
            
            % create a new figure relative to the figure window
            set(Hf,'Units','Pixels');
            gcfpos = get(Hf,'Position');
            set(Hf,'Units','Normalized');
            
            % open the calibration figure
            fpos(4) = 0.3*tb_width ;    % Fig height
            fpos(3) = tb_width ;        % Fig width
            fpos(1) = gcfpos(1)+0.5*gcfpos(3)-0.5*fpos(3);
            fpos(2) = gcfpos(2)+0.5*gcfpos(4)-0.5*fpos(4);
            
            % open a new options figure
            Hcal = figure('Name','Calibration Length','Units','pixels','Position',fpos);
            Hcal.NumberTitle = 'off';
            Hcal.Color = color.bg;
            Hcal.MenuBar = 'none';
            Hcal.ToolBar = 'none';
            Hcal.WindowStyle = 'modal';
            
            % populate the figure with buttons
            x = linspace(0.02,0.98,4);
            y = linspace(0.02,0.98,3);
            w = 0.96*(x(2)-x(1));
            h = 0.96*(y(2)-y(1));
            y = fliplr(y(1:end-1));
            
            % create the controls
            uicontrol('String','Length',...
                'Style','text',...
                'HorizontalAlignment','left',...
                'Units','normalized',...
                'FontSize',fontsize(2),...
                'Position',[x(1),y(1),w,h],...
                'Parent',Hcal);
            Hb.length = uicontrol('String',num2str(calib_length),...
                'ToolTipString','Define the real length (in real units) of the object you are about to Calibrate on',...
                'Style','Edit',...
                'HorizontalAlignment','center',...
                'Units','normalized',...
                'FontSize',fontsize(2),...
                'Position',[x(2),y(1),w,h],...
                'Parent',Hcal);
            Hb.unit = uicontrol('String',unit_lst,...
                'ToolTipString','Select the unit',...
                'Style','popupmenu',...
                'Value',unit_val,...
                'Units','normalized',...
                'FontSize',fontsize(2),...
                'Position',[x(3),y(1),w,h],...
                'Parent',Hcal);
            uicontrol('String','Ok',...
                'Style','pushbutton',...
                'Units','normalized',...
                'FontSize',fontsize(2),...
                'Position',[x(1),y(2),w,h],...
                'Parent',Hcal,...
                'call',{@calibopt_eval,'ok'});
            uicontrol('String','Cancel',...
                'Style','pushbutton',...
                'Units','normalized',...
                'FontSize',fontsize(2),...
                'Position',[x(2),y(2),w,h],...
                'Parent',Hcal,...
                'call',{@calibopt_eval,'cancel'});
            
            % bring toolbox to the front
            figure(Hcal);
            drawnow
            
            % wait for the user to answer the question
            uiwait(Hcal)
            
            % start drawing the calibration object
            measure_fun([],[],'Calibration')
        elseif strcmpi(type,'apply')
            % list of selected images
            selection = Hb.imlist.Value;
            i = currentfig;
            if A(i).cal == 0
                set(Hs,'String','The current image is not calibrated, nothing applied');
                return
            end
            c = A(i).cal;
            unit = A(c).unit;
            pixelsize = A(c).pixelsize;
            for k = selection
                A(k).pixelsize = pixelsize;
                A(k).unit = unit;
                A(k).cal = c;
                % update the measurement objects
                update_obj(A(k).obj);
            end
            set(Hs,'String','The current image calibration is applied to the selection')
        elseif strcmpi(type,'clear')
            selection = Hb.imlist.Value;
            c = 0;
            unit = [];
            pixelsize = [];
            for k = selection
                A(k).pixelsize = pixelsize;
                A(k).unit = unit;
                A(k).cal = c;
                
                % delete calibration objects
                j = find(arrayfun(@(x) strcmpi(x.type,'Calibration'),A(k).obj(:)));
                not_j = setdiff(1:numel(A(k).obj),j);
                
                % delete the plot object
                if isfield(A(k).obj,'hdl') && ~isempty(A(k).obj(j).hdl)
                    delete([A(k).obj(j).hdl]);
                end
                % delete the measurement
                A(k).obj = A(k).obj(not_j);
                
                % update the measurement objects
                update_obj(A(k).obj);
            end
            set(Hs,'String','Calibration cleared for selected images')
        end
    end

% ---------------------------------------------
    function calibopt_eval(varargin)
        % when ok or cancel is pressed in the calibration pop-up
        type = varargin{3};
        if strcmpi(type,'ok')
            calib_length = str2double(Hb.length.String);
            unit_val = Hb.unit.Value;
        else
            calib_length = 1;
            unit_val = unit_default;
        end
        delete(Hcal);
    end

% ---------------------------------------------
    function measure_fun(varargin)
        % function is called upon pressing any of the measurement buttons.
        % This function is also used by some other functions to initiate a
        % measurement, for example on a keypress, or following a previous
        % measurement
        if isempty(A)
            set(Hs,'String','No image defined, aborting measurement');
            return
        end
        
        % clear the temporary measurement (if any)
        reset_globals;

        if ishandle(Htmp)
            delete(Htmp);
        end
        
        % bring figure to the front
        figure(Hf);
        
        % disable any active toolbar buttons
        UnToggleToolBar;
        
        type = varargin{3};
        if strcmpi(type,'null')
            current_measure_type = 'null';
            set(Ha,'XLim',userxlim,'YLim',userylim);
            set(Hdrag,'XData',NaN,'YData',NaN);
            set(Hf,'Pointer',pointer{1});
            set(Hf,'WindowButtonMotionFcn',@none_move)
            set(Hf,'WindowButtonDownFcn',@null_fun)
            set(Hf,'WindowButtonUpFcn',@null_fun)
        elseif strcmpi(type,'Calibration')
            current_measure_type = 'Calibration';
            Htmp = create_obj('Calibration');
            Nclicks = 2;
            set(Hf,'Pointer',pointer{2});
            set(Hf,'WindowButtonMotionFcn',@calib_move)
            set(Hf,'WindowButtonDownFcn',@addpoint)
            set(Hf,'WindowButtonUpFcn',@null_fun)
        elseif strcmpi(type,'Distance')
            current_measure_type = 'Distance';
            Htmp = create_obj('Distance');
            Nclicks = 2;
            set(Hf,'Pointer',pointer{2});
            set(Hf,'WindowButtonMotionFcn',@distance_move)
            set(Hf,'WindowButtonDownFcn',@addpoint)
            set(Hf,'WindowButtonUpFcn',@null_fun)
        elseif strcmpi(type,'Caliper')
            current_measure_type = 'Caliper';
            Htmp = create_obj('Caliper');
            Nclicks = 3;
            set(Hf,'Pointer',pointer{2});
            set(Hf,'WindowButtonMotionFcn',@caliper_move)
            set(Hf,'WindowButtonDownFcn',@addpoint)
            set(Hf,'WindowButtonUpFcn',@null_fun)
        elseif strcmpi(type,'Polyline')
            current_measure_type = 'Polyline';
            Htmp = create_obj('Polyline');
            Nclicks = MaxPolyline;
            set(Hf,'Pointer',pointer{2});
            set(Hf,'WindowButtonMotionFcn',@polyline_move)
            set(Hf,'WindowButtonDownFcn',@addpoint)
            set(Hf,'WindowButtonUpFcn',@null_fun)
        elseif strcmpi(type,'Spline')
            current_measure_type = 'Spline';
            Htmp = create_obj('Spline');
            Nclicks = MaxPolyline;
            set(Hf,'Pointer',pointer{2});
            set(Hf,'WindowButtonMotionFcn',@spline_move)
            set(Hf,'WindowButtonDownFcn',@addpoint)
            set(Hf,'WindowButtonUpFcn',@null_fun)
        elseif strcmpi(type,'Circle')
            current_measure_type = 'Circle';
            Htmp = create_obj('Circle');
            Nclicks = 2;
            set(Hf,'Pointer',pointer{2});
            set(Hf,'WindowButtonMotionFcn',@circle_move)
            set(Hf,'WindowButtonDownFcn',@addpoint)
            set(Hf,'WindowButtonUpFcn',@null_fun)
        elseif strcmpi(type,'Angle')
            current_measure_type = 'Angle';
            Htmp = create_obj('Angle');
            Nclicks = 3;
            set(Hf,'Pointer',pointer{2});
            set(Hf,'WindowButtonMotionFcn',@angle_move)
            set(Hf,'WindowButtonDownFcn',@addpoint)
            set(Hf,'WindowButtonUpFcn',@null_fun)
        elseif strcmpi(type,'Edit')
            current_measure_type = 'Edit';
            if ShowAll
                selection = 1:numel(A);
            else
                selection = Hb.imlist.Value;
            end
            search_points_update(selection)
            set(Hs,'String','Edit: drag a point to a new location');
            set(Hf,'WindowButtonMotionFcn',@point_search)
            set(Hf,'WindowButtonDownFcn',@drag_buttondown)
            set(Hf,'WindowButtonUpFcn',@drag_buttonup)
            set(Hf,'Pointer',pointer{2});
        elseif strcmpi(type,'Delete')
            if ShowAll
                selection = 1:numel(A);
            else
                selection = Hb.imlist.Value;
            end
            search_points_update(selection)
            current_measure_type = 'Delete';
            set(Hs,'String','Delete: select an object to Delete');
            set(Hf,'WindowButtonMotionFcn',@point_search)
            set(Hf,'WindowButtonDownFcn',@delete_buttondown)
            set(Hf,'WindowButtonUpFcn',@null_fun)
            set(Hf,'Pointer',pointer{2});
        elseif strcmpi(type,'Copy')
            if ShowAll
                selection = 1:numel(A);
            else
                selection = Hb.imlist.Value;
            end
            search_points_update(selection)
            current_measure_type = 'Copy';
            set(Hs,'String','Copy: select an object to Copy');
            set(Hf,'WindowButtonMotionFcn',@point_search)
            set(Hf,'WindowButtonDownFcn',@copy_buttondown)
            set(Hf,'WindowButtonUpFcn',@null_fun)
            set(Hf,'Pointer',pointer{2});
        end
        % update the status bar if not Edit,Delete,Copy
        if ismember(current_measure_type,{'Calibration';'Distance';'Caliper';'Circle';'Angle';'Polyline';'Spline'})
            Hs.String = sprintf('%s (%d/%d): select the next point',current_measure_type,click_count,Nclicks);
        end        
    end

% ---------------------------------------------
    function save_fun(varargin)
        % saving the results
        type = varargin{3};
        if strcmpi(type,'SaveProject')
            % prompt for a filename to save to
            [filename,pathname] = uiputfile(fullfile(currentpath,'measuretool.mat'),'Save file name');
            if filename == 0
                set(Hs,'string','Save project aborted.');
                return
            end
            currentpath = pathname;
            set(Hs,'string','Writing .mat...');
            mt_data = output_fun;
            save(fullfile(pathname,filename),'-v7.3','mt_data');
            set(Hs,'string',sprintf('%s saved',filename));
        elseif strcmpi(type,'LoadProject')
            % prompt for a filename to read
            [filename,pathname] = uigetfile(fullfile(currentpath,'*.mat'),'Load a project');
            if filename == 0
                set(Hs,'string','Load project aborted.');
                return
            end
            currentpath = pathname;
            set(Hs,'string','Reading .mat...');
            B = load(fullfile(pathname,filename));
            if ~isfield(B,'mt_data')
                set(Hs,'string','mt_data not found, load project aborted.');
                return
            end
            B = B.mt_data;
            structload_fun(B);
            
            set(Hs,'string',sprintf('%s loaded',filename));
        elseif strcmpi(type,'SaveText')
            % save to a .txt
            if isempty(A) || ~isfield(A,'filename')
                set(Hs,'string','No images loaded, nothing to be saved');
                return
            end
            [filename,pathname] = uiputfile(fullfile(currentpath,'measuretool.txt'),'Save to text file');
            if filename == 0
                set(Hs,'string','Save to text file aborted.');
                return
            end
            currentpath = pathname;
            set(Hs,'string','Writing .txt...');
            
            Nim = numel(A);
            Nm = arrayfun(@(x) numel(x.obj),A);
            
            % open file for writing (and trunctate)
            fid = fopen(fullfile(pathname,filename),'wt+');
            
            % Write the header
            % ------------------
            fprintf(fid,'Data file created by measuretool.m \r\n');
            fprintf(fid,'=========================================== \r\n');
            fprintf(fid,'Date:                    %s \r\n',datestr(now));
            fprintf(fid,'Number of images:        %d \r\n',Nim);
            fprintf(fid,'Number of Measurements:  %d \r\n',sum(Nm));
            fprintf(fid,'= End of Header =========================== \r\n');
            fprintf(fid,'\r\n');
            
            % Section 1
            % ------------------            
            fprintf(fid,'= Measurement Table ======================= \r\n');
            fprintf(fid,'%3s, %3s, %11s, %13s, %5s, %s \r\n','i','j','type','val','unit','filename (i = image number, j = measurement number)');
            fprintf(fid,'------------------------------------------- \r\n');
            for i = 1:Nim
                if isempty(A(i).obj) || ~isfield(A(i).obj,'type')
                    continue
                end
                val = ismember(unit_str,A(i).unit);
                unit = unit_lst{val};
                fname = basename(A(i).filename);
                for j = 1:Nm(i)
                    type = A(i).obj(j).type;
                    val = A(i).obj(j).val_px;
                    fprintf(fid,'%3d, %3d, %11s, %13.6e, %5s, %s \r\n',i,j,type,val,unit,fname);
                end
            end
            
            % Section 2
            % ------------------            
            fprintf(fid,'=========================================== \r\n');
            fprintf(fid,'\r\n');
            fprintf(fid,'= Additional Data ========================= \r\n');
            % populate intensity data
            get_intensities;
            for i = 1:Nim
                pixelsize = A(i).pixelsize;
                if isempty(pixelsize)
                    pixelsize = [1 1 1];
                end
                val = ismember(unit_str,A(i).unit);
                unit = unit_lst{val};
                fprintf(fid,'Filename           : %s \r\n',A(i).filename);
                fprintf(fid,'Pixelsize          : %13.6e %s/px \r\n',pixelsize(1),unit);
                fprintf(fid,'Calibration Length : %13.6e %s \r\n',pixelsize(2),unit);
                fprintf(fid,'Calibration Length : %13.6e %s \r\n',pixelsize(3),'px');
                if isempty(A(i).obj) || ~isfield(A(i).obj,'points')
                    if i < Nim
                        fprintf(fid,'------------------------------------------- \r\n');
                    end
                    continue
                end
                unit = unit_lst{ismember(unit_str,A(i).unit)};
                for j = 1:Nm(i)
                    type = A(i).obj(j).type;
                    val = A(i).obj(j).val_px;
                    fprintf(fid,'Measurement %d: %s, %13.6e %s \r\n',j,type,val,unit);
                    x = A(i).obj(j).points(:,1);
                    y = A(i).obj(j).points(:,2);
                    I = A(i).obj(j).intensity;
                    rgb = size(I,2) == 3;
                    if rgb
                        fprintf(fid,'%13s, %13s, %13s, %13s, %13s\r\n','x','y','R','G','B');
                        for p = 1:numel(x)
                            fprintf(fid,'%13.6e, %13.6e, %13.6e, %13.6e, %13.6e\r\n',x(p),y(p),I(p,:));
                        end
                    else
                        fprintf(fid,'%13s, %13s, %13s\r\n','x','y','I');
                        for p = 1:numel(x)
                            fprintf(fid,'%13.6e, %13.6e, %13.6e\r\n',x(p),y(p),I(p,:));
                        end
                    end
                end
                if i < Nim
                    fprintf(fid,'------------------------------------------- \r\n');
                end
            end
            fprintf(fid,'= End of File ============================= \r\n');
            fclose(fid);
            set(Hs,'string',sprintf('%s written',filename));
            
        elseif strcmpi(type,'SavePNG')
            % save to png
            if isempty(A) || ~isfield(A,'filename')
                set(Hs,'string','No images loaded, nothing to be saved');
                return
            end
            % prompt for a filename to save to
            [filename,pathname] = uiputfile(fullfile(currentpath,'measuretool.png'),'Save file name');
            if filename == 0
                set(Hs,'string','Save to png aborted.');
                return
            end
            currentpath = pathname;
            set(Hs,'string','Writing png...');
            
            % prepare the figure
            set(Hf,'Units','Pixels');
            savepos = get(Hf,'Position');
            set(Hf,'Units','Normalized');
            set(Hf,'PaperUnits','inches','PaperPosition',savepos.*[0 0 1e-2 1e-2])
            
            % save to file
            set([Hc, Ht],'Visible','off');
            print(Hf,fullfile(pathname,filename),'-dpng','-r200')
            set([Hc, Ht],'Visible','on');
            
            % status
            set(Hs,'string',sprintf('%s saved',filename));
        elseif strcmpi(type,'SavePDF')
            % save to pdf
            if isempty(A) || ~isfield(A,'filename')
                set(Hs,'string','No images loaded, nothing to be saved');
                return
            end
            % prompt for a filename to save to
            [filename,pathname] = uiputfile(fullfile(currentpath,'measuretool.pdf'),'Save file name');
            if filename == 0
                set(Hs,'string','Save to pdf aborted.');
                return
            end
            currentpath = pathname;
            set(Hs,'string','Writing pdf...');
            
            % prepare the figure
            set(Hf,'Units','Pixels');
            savepos = get(Hf,'Position');
            set(Hf,'Units','Normalized');
            set(Hf,'PaperUnits','inches','PaperPosition',savepos.*[0 0 1e-2 1e-2])
            set(Hf,'PaperSize',savepos(3:4).*[1e-2 1e-2])
            
            % save to file
            set([Hc, Ht],'Visible','off');
            print(Hf,fullfile(pathname,filename),'-dpdf')
            set([Hc, Ht],'Visible','on');
            
            % status
            set(Hs,'string',sprintf('%s saved',filename));
        end
    end

% ---------------------------------------------
    function options_fun(varargin)
        % get the new settings
        PlotColors(1) = Hb.plotcolor(1).Value;
        PlotColors(2) = Hb.plotcolor(2).Value;
        PlotMarkers(1) = Hb.plotmarker(1).Value;
        PlotMarkers(2) = Hb.plotmarker(2).Value;
        MarkerSize = eval(Hb.markersize.String);
        fontsize(3) = eval(Hb.fontsize.String);
        TextBoxAlpha = eval(Hb.textboxalpha.String);
        TextBoxAlpha = min(max(TextBoxAlpha,0),1);
        Hb.textboxalpha.String = sprintf('%.2f',TextBoxAlpha);
        NumberFormat = Hb.NumberFormat.String;
        if ~regexp(NumberFormat,'(?<!%)%(\d+\$)?[ +#-]*(\d+|\*)?(\.\d*)?[bt]?[diuoxXfeEgGcs]')
            Hs.String = sprintf('Invalid Number Format %s, reverting to %%.2f',NumberFormat);
            NumberFormat = '%.4g';
            Hb.NumberFormat.String = NumberFormat;
            
        end
        ShowAll = Hb.showall.Value;
        AutoEdit = Hb.autoedit.Value;
        ZoomSelect = Hb.zoomselect.Value;
        ZoomBox = eval(Hb.zoombox.String);
        ZoomBox = max(ZoomBox,50);
        Hb.ZoomBox.String = sprintf('%.0f',ZoomBox);
        Npoints = eval(Hb.Npoints.String);
        Npoints = max(round(Npoints),2);
        Hb.Npoints.String = sprintf('%d',Npoints);
        MaxPolyline = eval(Hb.MaxPolyline.String);
        MaxPolyline = max(round(MaxPolyline),1);
        Hb.MaxPolyline.String = sprintf('%d',MaxPolyline);
        
        % update the figures
        Hp1 = findobj(Ha,'tag','measuretool_p1_markers');
        Hp2 = findobj(Ha,'tag','measuretool_p2_markers');
        Hp3 = findobj(Ha,'tag','measuretool_p1_nomarkers');
        Hp4 = findobj(Ha,'tag','measuretool_p2_nomarkers');
        Hp5 = findobj(Ha,'tag','measuretool_text');
        if ~isempty(Hp1)
            set(Hp1,'Color',color.val(PlotColors(2),:),'Marker',markers{PlotMarkers(2)},'MarkerSize',MarkerSize,'LineWidth',LineWidth(2));
        end
        if ~isempty(Hp2)
            set(Hp2,'Color',color.val(PlotColors(1),:),'Marker',markers{PlotMarkers(1)},'MarkerSize',MarkerSize,'LineWidth',LineWidth(1));
        end
        if ~isempty(Hp3)
            set(Hp3,'Color',color.val(PlotColors(2),:),'Marker','none','MarkerSize',MarkerSize,'LineWidth',LineWidth(2));
        end
        if ~isempty(Hp4)
            set(Hp4,'Color',color.val(PlotColors(1),:),'Marker','none','MarkerSize',MarkerSize,'LineWidth',LineWidth(1));
        end
        if ~isempty(Hp5)
            set(Hp5,'Color',color.val(PlotColors(1),:),'FontSize',fontsize(3),'BackgroundColor',[color.val(PlotColors(2),:),TextBoxAlpha]);
        end
        set(Hdrag,'MarkerSize',MarkerSize+4);
        
        % set visibility state of objects
        for i = 1:numel(A)
            if ShowAll || (i == currentfig)
                visible = 'on';
            else
                visible = 'off';
            end
            if ~isfield(A,'obj')
                continue
            end
            update_obj(A(i).obj);
            for k = 1:numel(A(i).obj)
                if ~isfield(A(i).obj,'hdl')
                    continue
                end
                set(A(i).obj(k).hdl,'Visible',visible);
            end
        end
        
        % update the list of selection points
        if ShowAll
            selection = 1:numel(A);
        else
            selection = Hb.imlist.Value;
        end
        search_points_update(selection)
    end

% ---------------------------------------------
    function options_button(varargin)
        % toggle the panel
        if strcmpi(Hp(6).Visible,'on')
            % switch options panel off
            set(Hp(6),'Visible','off');
            set(Hp(1:5),'Visible','on');
        else
            % switch options panel on
            set(Hp(6),'Visible','on');
            set(Hp(1:5),'Visible','off');
        end
    end


% =====================================================
% Helper Functions
% =====================================================

% ---------------------------------------------
    function a = textangle(a)
        % function to rotate text along a line (keeping text mostly upright)
        a = a - floor((a+90)./180)*180;
        % catch some weird cases
        if isempty(a) || isnan(a) || isinf(a)
            a = 0;
        end
    end

% ---------------------------------------------
    function reset_globals(varargin)
        click_count = 0;
        click_data = [];
        currentpoint = [];
        currentpoint_index = [];
        drag_moveall = false;
        zoom_flag = false;
        copy_obj_in_memory = [];
    end

% ---------------------------------------------
    function reset_fun(varargin)
        % this will completely clear the GUI bringing it to the initial
        % state
        
        reset_globals;
        current_measure_type = 'null';
        if ishandle(Htmp)
            delete(Htmp);
        end
        for i = 1:numel(A);
            if ~isfield(A,'obj')
                continue
            end
            if ~isfield(A(i).obj,'hdl')
                continue
            end
            for k = 1:numel(A(i).obj)
                delete(A(i).obj(k).hdl);
            end
        end
        
        A = [];
        currentfig = [];
        IMG = zeros(10,10);
        [imsize(1), imsize(2), imsize(3)] = size(IMG);
        userxlim = [1, imsize(2)];
        userylim = [1, imsize(1)];
        
        Hb.imlist.String = {};
        Hb.imlist.Value = 1;
        
        set(Hi,'CData',IMG);
        set(Ha,'XLim',userxlim,'YLim',userylim);
        set(Hdrag,'XData',NaN,'YData',NaN);
        set(Hf,'Pointer',pointer{1});
        set(Hf,'WindowButtonMotionFcn',@none_move)
        set(Hf,'WindowButtonDownFcn',@null_fun)
        set(Hf,'WindowButtonUpFcn',@null_fun)
        set(Hs,'String','...')
    end

% ---------------------------------------------
    function cellstrload_fun(B)
        % load list of file names from a cell array
        
        % clear the current data (if any)
        reset_fun;
        
        % load the new data
        Nim = numel(B);
        for i = 1:Nim
            filename = B{i};
            if ~exist(filename,'file')
                set(Hs,'string',sprintf('image file %s missing, skipping...',B(i).filename));
                warning('image file %s missing, skipping...',B(i).filename);
                pause(1);
                continue
            end
            A(i).filename = filename;
            Hb.imlist.String{i} = basename(filename);
            
            A(i).pixelsize = [];
            A(i).unit = unit_str(unit_default);
            A(i).cal = 0;
            A(i).obj = [];
        end
        Hb.imlist.Value = 1;
        image_fun([],[],'select')
    end


% ---------------------------------------------
    function structload_fun(B)
        % load data from a structure
        
        % clear the current data (if any)
        reset_fun;
        
        % load the new data
        Nim = numel(B);
        for i = 1:Nim
            if ~exist(B(i).filename,'file')
                set(Hs,'string',sprintf('image file %s missing, skipping...',B(i).filename));
                warning('image file %s missing, skipping...',B(i).filename);
                pause(1);
                continue
            end
            A(i).filename = B(i).filename;
            Hb.imlist.String{i} = basename(B(i).filename);
            if isfield(B,'unit') && ~isempty(B(i).unit)
                A(i).unit = B(i).unit;
                unit_val = find(ismember(unit_str,A(i).unit));
            else
                A(i).unit = [];
                unit_val = [];
            end
            if isempty(unit_val)
                unit_val = unit_default;
                A(i).unit = unit_str(unit_default);
            end
            if isfield(B,'pixelsize') && ~isempty(B(i).pixelsize)
                A(i).pixelsize = B(i).pixelsize;
            else
                A(i).pixelsize = [];
            end
            if numel(A(i).pixelsize == 3)
                calib_length = A(i).pixelsize(2);
            else
                calib_length = 1;
            end
            if isfield(B,'cal') && ~isempty(B(i).cal)
                A(i).cal = B(i).cal;
            else
                A(i).cal = 0;
            end
            if isfield(B,'obj') && ~isempty(B(i).obj)
                A(i).obj = B(i).obj;
            else
                A(i).obj = [];
            end
            Nk = numel(A(i).obj);
            for k = 1:Nk
                if ~isfield(A(i).obj,'points') || ~isfield(A(i).obj,'type')
                    continue
                end
                if isempty(A(i).obj(k).points) || isempty(A(i).obj(k).type)
                    continue
                end
                % create the plot objects
                type = A(i).obj(k).type;
                A(i).obj(k).hdl = create_obj(type);
                
                currentfig = i;
                update_figure;
                update_measurement(i,k);
            end
        end
        Hb.imlist.Value = 1;
        image_fun([],[],'select')
    end

% ---------------------------------------------
    function H = create_obj(type)
        % function used to create the plot objects to go with a measurement
        % object. Each measurement is drawn using 5 plot objects:
        %    1 : Main curve using color one
        %    2 : Main curve using color two
        %    3 : Secondary curve using color one
        %    4 : Secondary curve using color two
        %    5 : Text box
        % some measurement objects don't need 3 and 4, but they are drawn
        % nevertheless for code simplicity
        
        % create the plot objects
        if strcmpi(type,'Calibration')
            H(1) = plot(NaN,NaN,'Parent',Ha,'Tag','measuretool_p1_markers','LineStyle',linestyles{1});
            H(2) = plot(NaN,NaN,'Parent',Ha,'Tag','measuretool_p2_markers','LineStyle',linestyles{2});
            H(3) = plot(NaN,NaN,'Parent',Ha,'Tag','measuretool_p1_markers','LineStyle',linestyles{1});
            H(4) = plot(NaN,NaN,'Parent',Ha,'Tag','measuretool_p2_markers','LineStyle',linestyles{2});
            H(5) = text(NaN,NaN,'Calibration','Parent',Ha,'Tag','measuretool_text');
        elseif strcmpi(type,'Distance')
            H(1) = plot(NaN,NaN,'Parent',Ha,'Tag','measuretool_p1_markers','LineStyle',linestyles{1});
            H(2) = plot(NaN,NaN,'Parent',Ha,'Tag','measuretool_p2_markers','LineStyle',linestyles{2});
            H(3) = plot(NaN,NaN,'Parent',Ha,'Tag','measuretool_p1_markers','LineStyle',linestyles{1});
            H(4) = plot(NaN,NaN,'Parent',Ha,'Tag','measuretool_p2_markers','LineStyle',linestyles{2});
            H(5) = text(NaN,NaN,'Distance','Parent',Ha,'Tag','measuretool_text');
        elseif strcmpi(type,'Caliper')
            H(1) = plot(NaN,NaN,'Parent',Ha,'Tag','measuretool_p1_markers','LineStyle',linestyles{1});
            H(2) = plot(NaN,NaN,'Parent',Ha,'Tag','measuretool_p2_markers','LineStyle',linestyles{2});
            H(3) = plot(NaN,NaN,'Parent',Ha,'Tag','measuretool_p1_markers','LineStyle',linestyles{1});
            H(4) = plot(NaN,NaN,'Parent',Ha,'Tag','measuretool_p2_markers','LineStyle',linestyles{2});
            H(5) = text(NaN,NaN,'Caliper','Parent',Ha,'Tag','measuretool_text');
        elseif strcmpi(type,'Polyline')
            H(1) = plot(NaN,NaN,'Parent',Ha,'Tag','measuretool_p1_markers','LineStyle',linestyles{1});
            H(2) = plot(NaN,NaN,'Parent',Ha,'Tag','measuretool_p2_markers','LineStyle',linestyles{2});
            H(3) = plot(NaN,NaN,'Parent',Ha,'Tag','measuretool_p1_markers','LineStyle',linestyles{1});
            H(4) = plot(NaN,NaN,'Parent',Ha,'Tag','measuretool_p2_markers','LineStyle',linestyles{2});
            H(5) = text(NaN,NaN,'Polyline','Parent',Ha,'Tag','measuretool_text');
        elseif strcmpi(type,'Spline')
            H(1) = plot(NaN,NaN,'Parent',Ha,'Tag','measuretool_p1_markers','LineStyle','none');
            H(2) = plot(NaN,NaN,'Parent',Ha,'Tag','measuretool_p2_markers','LineStyle','none');
            H(3) = plot(NaN,NaN,'Parent',Ha,'Tag','measuretool_p1_nomarkers','LineStyle',linestyles{1});
            H(4) = plot(NaN,NaN,'Parent',Ha,'Tag','measuretool_p2_nomarkers','LineStyle',linestyles{2});
            H(5) = text(NaN,NaN,'Spline','Parent',Ha,'Tag','measuretool_text');
        elseif strcmpi(type,'Circle')
            H(1) = plot(NaN,NaN,'Parent',Ha,'Tag','measuretool_p1_markers','LineStyle',linestyles{1});
            H(2) = plot(NaN,NaN,'Parent',Ha,'Tag','measuretool_p2_markers','LineStyle',linestyles{2});
            H(3) = plot(NaN,NaN,'Parent',Ha,'Tag','measuretool_p1_nomarkers','LineStyle',linestyles{1});
            H(4) = plot(NaN,NaN,'Parent',Ha,'Tag','measuretool_p2_nomarkers','LineStyle',linestyles{2});
            H(5) = text(NaN,NaN,'Circle','Parent',Ha,'Tag','measuretool_text');
        elseif strcmpi(type,'Angle')
            H(1) = plot(NaN,NaN,'Parent',Ha,'Tag','measuretool_p1_markers','LineStyle',linestyles{1});
            H(2) = plot(NaN,NaN,'Parent',Ha,'Tag','measuretool_p2_markers','LineStyle',linestyles{2});
            H(3) = plot(NaN,NaN,'Parent',Ha,'Tag','measuretool_p1_nomarkers','LineStyle',linestyles{1});
            H(4) = plot(NaN,NaN,'Parent',Ha,'Tag','measuretool_p2_nomarkers','LineStyle',linestyles{2});
            H(5) = text(NaN,NaN,'Angle','Parent',Ha,'Tag','measuretool_text');
        else
            error('unknown type %s',type)
        end
        
        % set their visual style
        set(H(1),'Color',color.val(PlotColors(2),:),'Marker',markers{PlotMarkers(2)},'LineWidth',LineWidth(2),'MarkerSize',MarkerSize);
        set(H(2),'Color',color.val(PlotColors(1),:),'Marker',markers{PlotMarkers(1)},'LineWidth',LineWidth(1),'MarkerSize',MarkerSize);
        set(H(3),'Color',color.val(PlotColors(2),:),'Marker','none','LineWidth',LineWidth(2),'MarkerSize',MarkerSize);
        set(H(4),'Color',color.val(PlotColors(1),:),'Marker','none','LineWidth',LineWidth(1),'MarkerSize',MarkerSize);
        set(H(5),'HorizontalAlignment','Center','VerticalAlignment','bottom','FontSize',fontsize(3),'Color',color.val(PlotColors(1),:));
        set(H(5),'EdgeColor','none','BackgroundColor',[color.val(PlotColors(2),:),TextBoxAlpha],'Margin',1)
        uistack(Hdrag,'top')
    end


% ---------------------------------------------
    function update_figure(varargin)
        % update the figure
        
        if isempty(A) || isempty(currentfig)
            return
        end
        
        % read the figure
        IMG = imread(A(currentfig).filename);
        set(Hi,'CData',IMG);
        oldsize = imsize;
        [imsize(1), imsize(2), imsize(3)] = size(IMG);
        
        % reset the zoom
        if ~all(imsize==oldsize)
            set(Ha,'XLim',[1, imsize(2)],'YLim',[1, imsize(1)]);
            userxlim = [1, imsize(2)];
            userylim = [1, imsize(1)];
        end
        
        % set visibility state of objects
        for i = 1:numel(A)
            if ShowAll || (i == currentfig)
                visible = 'on';
            else
                visible = 'off';
            end
            if ~isfield(A,'obj')
                continue
            end
            for k = 1:numel(A(i).obj)
                set(A(i).obj(k).hdl,'Visible',visible);
            end
        end
        
        if A(currentfig).cal == 0
            % default calibration
            r = 1;
            length = calib_length;
            pixelsize = length./r;
            unit = unit_str{unit_default};
        else
            % load the previous calibration
            c = A(currentfig).cal;
            pixelsize = A(c).pixelsize;
            unit = A(c).unit;
        end
        str = sprintf([NumberFormat ' %s'],pixelsize(1),unit);
        set(Hb.pixelsize,'String',str);
        if A(currentfig).cal == 0
            set(Ht,'String',sprintf('%d, %s (not calibrated)',currentfig,Hb.imlist.String{currentfig}));
        elseif A(currentfig).cal == currentfig
            set(Ht,'String',sprintf('%d, %s (calibrated, px = %s)',currentfig,Hb.imlist.String{currentfig},str));
        else
            set(Ht,'String',sprintf('%d, %s (calibration from %d, px = %s)',currentfig,Hb.imlist.String{currentfig},A(currentfig).cal,str));
        end
    end

% ---------------------------------------------
    function update_obj(obj)
        % update the text boxes for all measurement objects in the array
        % obj
        
        pixelsize = A(currentfig).pixelsize;
        unit = A(currentfig).unit;
        if isempty(pixelsize)
            pixelsize = [1, 1, 1];
            unit = 'px';
        end
        for k = 1:numel(obj)
            type = obj(k).type;
            hdl = obj(k).hdl;
            val = obj(k).val_px;
            if isempty(hdl)
                continue
            end
            if strcmpi(type,'Calibration')
                set(hdl(5),'String',sprintf([NumberFormat ' px'],val));
            elseif strcmpi(type,'Angle')
                set(hdl(5),'String',sprintf([NumberFormat ' %s'],val,deg));
            else
                set(hdl(5),'String',sprintf([NumberFormat ' %s'],val.*pixelsize(1),unit));
            end
        end
    end

% -----------------------------------------------
    function phi = buildshapefun(v)
        % Catmull-Rom Shapefunctions
        alpha = 0.5;
        % Catmull-Rom parameter: 0.5 = Centripetal, 0 = Uniform, 1 = Chordal
        Nv = size(v,1);
        
        if Nv < 4
            phi = eye(Nv);
            return
        end
        
        % compute point distances
        s = hypot(diff(v(:,1)),diff(v(:,2)));
        
        % add two points
        s = [s(1) ; s ; s(end)];
        
        % parameterization
        t = [0; cumsum(s.^alpha)];
        Nt = numel(t);
        
        % parameter space
        ti = transpose(linspace(t(2),t(Nt-1),Npoints));
        
        A1 = zeros(Npoints,4);
        A2 = zeros(Npoints,4);
        A3 = zeros(Npoints,4);
        B1 = zeros(Npoints,4);
        B2 = zeros(Npoints,4);
        phi = zeros(Npoints,Nv+2);
        
        % Only the first and the last two shape functions change live, so this
        % function could be faster of the loop is not from 0 to end, but i'm to
        % lazy to fix it.
        for i = 1:Nv-1;
            p = (i:i+3);
            
            t1 = t(i+0);
            t2 = t(i+1);
            t3 = t(i+2);
            t4 = t(i+3);
            
            I = (ti >= t2) & (ti <= t3);
            u = ti(I);
            
            % Catmull-Rom (Barry and Goldman's formulation)
            A1(I,1) = (t2-u)./(t2-t1);
            A1(I,2) = (u-t1)./(t2-t1);
            A2(I,2) = (t3-u)./(t3-t2);
            A2(I,3) = (u-t2)./(t3-t2);
            A3(I,3) = (t4-u)./(t4-t3);
            A3(I,4) = (u-t3)./(t4-t3);
            
            B1(I,:)  = repmat((t3-u)./(t3-t1),1,4).*A1(I,:) + repmat((u-t1)./(t3-t1),1,4).*A2(I,:);
            B2(I,:)  = repmat((t4-u)./(t4-t2),1,4).*A2(I,:) + repmat((u-t2)./(t4-t2),1,4).*A3(I,:);
            phi(I,p) = repmat((t3-u)./(t3-t2),1,4).*B1(I,:) + repmat((u-t2)./(t3-t2),1,4).*B2(I,:);
        end
        
        % fix the first and last shapefunctions
        phi(:,2) = phi(:,1) + phi(:,2);
        phi(:,Nv+1) = phi(:,Nv+1) + phi(:,Nv+2);
        phi = phi(:,2:Nv+1);
    end

% ---------------------------------------------
    function [x, y, D] = Caliper(x,y)
        % The perpendicular Distance (http://mathworld.wolfram.com/Point-LineDistance2-Dimensional.html)
        D = ( (x(2)-x(1))*(y(1)-y(3)) - (x(1)-x(3))*(y(2)-y(1)) );
        
        % now determine the location of the fourth point for plotting
        dx = x(1)-x(2);
        dy = y(1)-y(2);
        dn = hypot(dx,dy);
        D  = D  / dn;
        dx = dx / dn;
        dy = dy / dn;
        x(4) = x(3) + D*dy;
        y(4) = y(3) - D*dx;
    end

% ---------------------------------------------
    function [x, y, r] = Circle(x,y)
        % get the center and radius from three points
        % https://en.wikipedia.org/wiki/Circumscribed_circle#Circumcenter_coordinates
        ax = x(1);
        ay = y(1);
        bx = x(2) - x(1);
        by = y(2) - y(1);
        cx = x(3) - x(1);
        cy = y(3) - y(1);
        d = 1/(2*(bx*cy - by*cx));
        x = ax + d * (cy*(bx^2+by^2) - by*(cx^2+cy^2));
        y = ay + d * (bx*(cx^2+cy^2) - cx*(bx^2+by^2));
        r = hypot((x-ax),(y-ay));
    end


% ---------------------------------------------
    function exitGUI(varargin)
        % is called when the user closes the figure window.
        if ishandle(Htb)
            delete(Htb)
        end
    end

% ---------------------------------------------
    function get_intensities(varargin)
        % interpolate the images at the x,y locations
        
        if ~isfield(A,'filename')  || ~isfield(A,'obj')
            return
        end
        
        Nim = numel(A);
        for i = 1:Nim
            if isempty(A(i).obj) || ~isfield(A(i).obj,'points')
                continue
            end
            
            % interpolator
            img = imread(A(i).filename);
            F = griddedInterpolant(double(img));
            rgb = ndims(img) == 3;
            
            Nobj = numel(A(i).obj);
            for j = 1:Nobj
                if isempty(A(i).obj(j).points)
                    A(i).obj(j).intensity = [];
                    continue
                end
                x = A(i).obj(j).points(:,1);
                y = A(i).obj(j).points(:,2);
                
                if rgb
                    N = numel(x);
                    x = repmat(x,1,3);
                    y = repmat(y,1,3);
                    z = repmat(1:3,N,1);
                    A(i).obj(j).intensity = F(y,x,z);
                else
                    A(i).obj(j).intensity = F(y,x);
                end
            end
        end
    end

% ---------------------------------------------
    function B = output_fun(varargin)
        % prepare the data structure for output
        
        % populate image intensities
        get_intensities;

        if ~isfield(A,'obj')
            return
        end
        
        % copy the data
        B = A;
        
        for i = 1:numel(A)
            % pre-multiply the units
            for j = 1:numel(A(i).obj)
                if isfield(A(i).obj(j),'val_px');
                    B(i).obj(j).val_unit = B(i).obj(j).val_px * B(i).pixelsize(1);
                end
            end
            
            % remove plot handles from the data
            if ~isempty(B(i).obj)
                B(i).obj = orderfields(rmfield(B(i).obj,'hdl'));
            end
        end
    end

% ---------------------------------------------
    function UnToggleToolBar
        % disable ui toggle buttons
        zoom(Hf,'off');
        pan(Hf,'off');
        rotate3d(Hf,'off');
        datacursormode(Hf,'off');
        brush(Hf,'off');
    end

% ---------------------------------------------
    function filename = basename(filename)
        % shorthand to get only the filename from a path
        [~,name,ext] = fileparts(filename);
        filename = [name, ext];
    end

% =====================================================
    function WindowScrollWheelFcn(varargin)
        % zoom local to the cursor
        p = get(Ha,'CurrentPoint');
        x = p(1,1);
        y = p(1,2);

        evnt = varargin{2};
        R = 1.02^evnt.VerticalScrollCount;
        
        width = diff(userxlim);
        height = diff(userylim);
        
        a = (x - userxlim(1))./width;
        userxlim(1) = x - a*R*width;
        userxlim(2) = R*width + userxlim(1);
        
        b = (y - userylim(1))./height;
        userylim(1) = y - b*R*height;
        userylim(2) = R*height + userylim(1);
        set(Ha,'XLim',userxlim,'YLim',userylim);
    end

% = Help =============================================
    function help_fun(varargin)
        % this function creates a new window with the following text inside
        % if the help is not open, otherwise it closes the help window
        txt = {;
            'This tool (measuretool) is intended for measuring on images.'
            'In order to do this the image needs to have some visual scale to calibrate the pixel to length ratio on, e.g. scale bar, ruler.'
            ''
            'Updates can be found at:'
            'http://www.mathworks.nl/matlabcentral/fileexchange/25964-image-measurement-utility'
            ''
            'Quick Help'
            '============================='
            ' - Add images to the list using the <Add> button'
            ' - Calibrate the image pixelsize using the <Calibrate> button'
            '      - This opens a popup which asks for the real length of the object you will calibrate on'
            '      - Pressing <OK> in the popup will close the popup'
            '      - Next, select the start and end point of the calibration object using the mouse'
            '      - The calibration can be modified later on if so desired using <Edit>'
            ' - Use the buttons in the <Measure> panel to start measuring'
            ' - Each measurement can be deleted using <Delete> or modified using <Edit>'
            ' - Look at the <Status> panel for guidance while using the different tools'
            ''
            'Help/Options/Reset'
            '============================='
            'These three buttons found at the top of the GUI are reasonably self explanatory:'
            '<Help>: Open this help panel.'
            '<Options>: Toggle the options tab (see more details below).'
            '<Reset>: Reset the GUI, this clears any data.'
            ''
            'Calibrate'
            '============================='
            'Each measurement depends on the calibration, so it is worth spending some time on getting it right. The proposed work flow is to roughly place the calibration object, then press <Edit> in the <Measure> panel and reposition each end-point to a more precise location by dragging it. The <Edit> mode allows zooming of the image using the buttons in the top toolbar. Accurate calibration is easily achieved by zooming near each end-point and placing the calibration nodes with sub-pixel accuracy. Alternatively, use <Zoom Select> or use the Mouse-Wheel to improve precise placement of the points.'
            ''
            'A few notes regarding calibration inheritance:'
            ' - A new calibration is stored in the current image'
            ' - Other selected images will inherit this calibration'
            ' - Currently uncalibrated images will inherit the first calibration'
            ' - Newly added images will inherit the calibration of the current image'
            ' - Inherited calibrations will also inherit future changes'
            ' - Use the <Apply> button to set the calibration of the current image to all selected images'
            ' - Use the <Clear> button to clear the calibration of all selected images'
            ''
            'Measure'
            '============================='
            'This panel holds the measurement tools. In general, the work flow is to use the left mouse button to add points, and the right mouse button the remove the most recently added point. When necessary (Polyline and Spline) use double click to finalize the measurement.'
            '<Distance>: measure the distance between two points.'
            '<Caliper>: measure the perpendicular distance between a line and a point. The first two clicks define the line, the third click finalizes the measurement.'
            '<Polyline>: measure the distance along a string of points.'
            '<Spline>: Like Polyline, except using a smoothly curved line (using a Catmull-Rom Spline basis).'
            '<Circle>: measure a radius using two points. The first point is the center, the second the radius.'
            '<Angle>: measure an angle between two lines. This tool requires three points ABC, the angle is the one between the line segments AB and BC.'
            ''
            'The remaining three buttons are for modifying measurements:'
            '<Edit>: After clicking this button, any visible node can be dragged to a new location. Hold [Control] or use the right mouse button to move all the nodes of the object as one.'
            '<Delete>: Delete an object by clicking on one of its nodes.'
            '<Copy>: Copy objects by click-and-place. The first left mouse click selects an object and makes a temporary copy. The second mouse click places the object. Use the right mouse button to not place a selected object.'
            ''
            'Save'
            '============================='
            '<Save Project>: Save the current state to a .mat file. These type of mat files can be loaded using this tool, or can be loaded directly in matlab, it contains one variable named "mt_data". See Outputs for information about the structuring of the data.'
            '<Load Project>: Load a previously saved project. The used image files are not saved in the project and the tool is expecting them to still reside in the same location. If an image is not found then it is skipped and the corresponding measurements will not be loaded.'
            '<Save to PNG>: Save the current figure window as a .png file'
            '<Save to PDF>: Save the current figure window as a .pdf file'
            '<Save to Text>: Write all the measurement data to a formatted text file. The text file contains two sections, the first is a table with one row per measurement. The second part of the file contains the raw data of each measurement including coordinates of all points used in the measurement and the gray-values (or RGB values) for each point. The data in this section is in pixels and can be converted to the proper units using the calibration data written in the same section.'
            ''
            'Options'
            '============================='
            'This panel can be shown by pressing the <Options> button at the top of the GUI, press this button again to go back to the other panels.'
            '<Plot Color>, <Plot Marker> and <Marker Size> control the visual style of the measurements. Each measurement is drawn using two plot curves on top of each other. The bottom one has a slightly wider linewidth. This improves contrast to the measure objects such that they easily are visible, even in images that have high contrast of themselves.'
            '<Font Size> and <Text Box Alpha> control the visual style of the text displayed next to a measurement object. The Text Box Alpha option controls the transparency of the background color. Set it to zero to hide the text box.'
            '<Number Format> determines how the numbers in the label are formatted, see the matlab formatSpec (e.g. sprintf) for more info. Examples are %.2f for floating point notation, %.4e for scientific notation, or use %g for a more automatic formatting.'
            '<Auto Edit> enable this option to automatically go in <Edit> mode after finalizing each measurement.'
            '<Zoom Select> enable this option for more precision. Now when adding a measurement point, the first mouse click zooms near the point of interest, the second mouse click actually places the point.'
            '<Zoom Box Size> this defines the size (width and hight) of the zoomed area when using Zoom Select.'
            '<Show All> enable this option to show all measurements from all images at the same time.'
            '<Number of Points> define how many points to use for the smooth curves, namely, Circle and Spline.'
            '<Max Polyline> set the maximum number of points in a Polyline or Spline, this way no double-click is required and the measurement is automatically finalized when N points are defined.'
            ''
            'Keyboard and Mouse Controls'
            '============================='
            'Some buttons have a keyboard shortcut indicated in parentheses behind their name, for example <Edit (E)>'
            'The mouse-wheel can be used at any moment to zoom in or out in the image.'
            ''
            'Inputs'
            '============================='
            'The tool accepts zero or one inputs as arguments. For the single argument there are two types:'
            ''
            ' A = measuretool(imgs), where imgs is a cellarray of strings of filenames,'
            '     allowing initialization with a predefined set of images'
            ''
            ' A = measuretool(A), alternatively preload the tool with a previously'
            '     generated data structure containing image paths and measurements'
            ''
            'Outputs'
            '============================='
            ' A = measuretool'
            ' The output A is a structure array with one array element per image with the following fields'
            ' A(i).filename     : a string specifying the path to the image'
            ' A(i).cal          : the array index pointing to the calibration'
            '                     A(i).cal == i for calibrated images '
            '                     A(i).cal == 0 for uncalibrated images'
            '                     A(i).cal ~= i for inherited images'
            ' A(i).pixelsize   : a three element vector with calibration values'
            '                    A(i).pixelsize(1) : the size of a pixel in real units'
            '                    A(i).pixelsize(2) : the real length used for calibration'
            '                    A(i).pixelsize(3) : the same length in pixels'
            ' A(i).unit        : string indicating the units specified during calibration'
            ' A(i).obj         : a structure array with one element per measurement with the following fields'
            ' obj(j).type      : the type of measurement (Distance, Angle, etc.)'
            ' obj(j).val_px    : the measurement value in pixels'
            ' obj(j).val_unit  : the measurement value in the specified units'
            ' obj(j).points    : the vertices of the measurement as a Nx2 matrix in pixels'
            ' obj(j).intensity : the image intensity at the vertex locations'
            '                    Nx1 matrix for grayscale'
            '                    Nx3 matrix for RGB'
            'Multiply the values in obj(j).val_px and obj(j).points by pixelsize(1) to apply the calibration and convert them to real units.'
            ''
            'Exiting the tool'
            '============================='
            'Closing either the image figure window or the toolbar figure window will exit the tool and output the structure with data (if an output is defined). Closing the figure window also closes the toolbar, however, closing the toolbar does not close the figure window.'
            ''
            'Changelog'
            '============================='
            'version 2.01 by Jan Neggers, Jan,2018'
            '   - changed the output structure to have both val_px and val_units to address some comments of '
            '     users expecting the obj.val output to be in the specified units.'
            ''
            'version 2.00 by Jan Neggers, Oct,2017'
            '   - Complete rewrite, optimized for more recent matlab versions'
            '   - New mouse interaction system, removing the IP toolbox requirement'
            ''
            'version 1.14 by Jan Neggers, Apr,09,2014'
            '   - added .bmp to the list of imagetypes (as suggested by Jie)'
            ''
            'version 1.13 by Jan Neggers, Jan,12,2012'
            '   - added feature to measure the intensity (as suggested by Jakub)'
            '   - included the "Plot" section in the help'
            '   - simplified the save to workspace structure'
            ''
            'version 1.12 by Jan Neggers, Dec,7,2011'
            '   - most GUI buttons are now disabled during measurements to prevent confusion'
            '   - added a "clear" button to reset the tool'
            '   - added more input checks for the "options" menu'
            ''
            'version 1.11 by Jan Neggers, Sept,29,2011'
            '   - minor update, added the possibility to use a figure window which is already open (e.g. measuretool(gcf))'
            '   - changed the zoom select from absolute to relative'
            '   - all buttons are now disabled during measurement'
            ''
            'version 1.10 by Jan Neggers, Sept,27,2011'
            '   - entire overhaul of the gui, added quite a few features, some of which as proposed by Mark Hayworth'
            ''
            'version 1.00 by Jan Neggers, Sept,22,2011'
            '   - fixed some bugs related to the help'
            '   - improved displaying in micrometers'
            '   - added the four <Save> buttons'
            ''
            'version 0.92 by Jan Neggers, Apr,06,2010'
            '   - fixed grayscale images showing in color (after comment from Till)'
            '   - improved help file displaying'
            ''
            'version 0.91 by Jan Neggers, Nov,30,2009'
            '   - first version'
            };
        
        if ishandle(Hh)
            delete(Hh)
        else
            % open a new figure window
            Hh = figure('Units','Normalized','OuterPosition',Hf.OuterPosition);
            Hh.Name = 'Measure Tool (Help)';
            
            uicontrol('Style','edit',...
                'String',txt,...
                'Max',2,...
                'Enable','inactive',...
                'units','normalized',...
                'BackgroundColor','w',...
                'HorizontalAlignment','left',...
                'Position',[0.01,0.01,0.99,0.99],...
                'FontSize',fontsize(3),...
                'FontName',fixwidthfont,...
                'Tag','help',...
                'Parent',Hh);
        end
    end


% =====================================================
% End of GUI
% =====================================================

uiwait(Htb);
% close calibration window
if ishandle(Hcal)
    delete(Hcal)
end
% close help window
if ishandle(Hh)
    delete(Hh)
end

% prepare the outputs
if nargout == 1
    varargout{1} = output_fun;
end

% End of main function
end

