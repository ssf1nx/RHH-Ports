global.scrScaleDisplay = function()
{
    var _dwidth = window_get_width();
    var _dheight = window_get_height();
    global.lastWindowWidth = _dwidth;
    global.lastWindowHeight = _dheight;
    
    if (global.dispBordered)
    {
        var windowAspectRatio = _dwidth / _dheight;
        var scaleFactor;
        
        if (windowAspectRatio > global.screenRatio)
            scaleFactor = _dheight / global.SCREEN_HEIGHT;
        else
            scaleFactor = _dwidth / global.SCREEN_WIDTH;
        
        if (global.integerScale)
            scaleFactor = max(floor(scaleFactor), 1);
        
        global.scaleScreenWidth = global.SCREEN_WIDTH * scaleFactor;
        global.scaleScreenHeight = global.SCREEN_HEIGHT * scaleFactor;
        global.scaleScreenX = (_dwidth - global.scaleScreenWidth) * 0.5;
        global.scaleScreenY = (_dheight - global.scaleScreenHeight) * 0.5;
    }
    else
    {
        global.scaleScreenWidth = _dwidth;
        global.scaleScreenHeight = _dheight;
        global.scaleScreenX = 0;
        global.scaleScreenY = 0;
    }
}
