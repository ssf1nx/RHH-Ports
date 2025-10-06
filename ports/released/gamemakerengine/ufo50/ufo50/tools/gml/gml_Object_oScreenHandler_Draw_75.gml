var _dwidth, _dheight;

_dwidth = window_get_width();
_dheight = window_get_height();
display_set_gui_size(_dheight * global.screenRatio, _dheight);

if (window_get_fullscreen())
    display_set_gui_maximize(1, 1, 0, 0);

if (do_screen)
{
    if (_dwidth != global.lastWindowWidth || _dheight != global.lastWindowHeight)
        scrScaleDisplay();
    
    gpu_set_tex_filter(global.dispFilter);
    draw_clear(c_black);
    draw_surface_stretched(application_surface, global.scaleScreenX, global.scaleScreenY, global.scaleScreenWidth, global.scaleScreenHeight);
    gpu_set_tex_filter(false);
}
else
{
    do_screen = true;
}