function car_bounce(arg0, arg1)
{
    with (arg0.obj)
    {
        var p = arg0.weight / (arg0.weight + arg1.weight);
        if (inv || arg1.obj.inv || arg1.obj.autopilot)
        {
            return 
            {
                x: xsp,
                y: ysp
            };
        }
        if ((lap < arg1.obj.lap && (arg1.obj.track_pos - track_pos) > 20 && !crash && is_player(arg1) && !is_player(arg0)) || arg0.ai_type == 6 || (!crash && is_player(arg1) && !is_player(arg0) && event_check_multiple([8])))
        {
            crash = 1000;
            crash_timer = 80;
            bigcrash = true;
            aggressor = arg1;
            sfx_play(snd_bigCrash, 0, 0);
            obj_main.camera[arg1.playernum].shake = 15;
            arg0.funny_scream = audio_play_sound_on(arg0.sfxEmit, (arg1.carindex == 18) ? snd_wilhelm : snd_serious, true, 0);
            zsp = -15;
            inair = true;
            grav = 0.4;
            if (event_check_type(9))
            {
                var _t = choose("GO AWAY", "GET OUT", "BYE BYE", "THATS RIGHT!");
                event_survival_add_time(3, _t);
                switch (_t)
                {
                    case "GO AWAY":
                        sfx_play(snd_goaway, 1, 0);
                        break;
                    case "THATS RIGHT!":
                        sfx_play(snd_thatsright, 1, 0);
                        break;
                }
            }
            if (event_check_type(8))
            {
                obj_timer.secs -= 2;
                obj_timer.shake = 20;
            }
            return 
            {
                x: xsp + (arg1.obj.xsp * 1.3),
                y: ysp + (arg1.obj.ysp * 1.3)
            };
        }
        var _fdir = point_direction(x, y, arg1.obj.x, arg1.obj.y);
        var _fdiff = angle_difference(_fdir, dir);
        var _spd = 
        {
            x: xsp,
            y: ysp
        };
        if (abs(_fdiff) < 18 || abs(_fdiff) > 162)
        {
            var _dot = dot_product(lengthdir_x(1, dir), lengthdir_y(1, dir), arg1.obj.xsp, arg1.obj.ysp);
            var _spdiff = _dot - spd;
            _spd.x += lengthdir_x(_spdiff * 2, dir) * (1 - p);
            _spd.y += lengthdir_y(_spdiff * 2, dir) * (1 - p);
            if (!arg0.cpu && car_crashsound == 0)
            {
                sfx_play(snd_crash, 1, 0);
                obj_main.camera[arg0.playernum].shake = abs(_spdiff * 2);
                car_crashsound = 6;
            }
        }
        else
        {
            var _dot = dot_product(lengthdir_x(1, dir - 90), lengthdir_y(1, dir - 90), arg1.obj.xsp, arg1.obj.ysp);
            if (!arg0.cpu)
            {
                wallhit = sign(_dot);
                if (car_crashsound == 0)
                {
                    sfx_play(snd_crash, 1, 0);
                    car_crashsound = 6;
                }
            }
        }
        return _spd;
    }
}
