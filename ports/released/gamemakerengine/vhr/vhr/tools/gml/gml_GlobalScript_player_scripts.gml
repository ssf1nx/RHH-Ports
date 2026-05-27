function top_landing()
{
    if (zsp > 5)
    {
        if (!parent.cpu && !parent.ghost && obj_main.camera[parent.playernum].target == parent.id)
        {
            sfx_play(snd_bigCrash, 1, 0);
            obj_main.camera[parent.playernum].shake = 30 - (100 / zsp);
            if (!parent.replay)
            {
                controller_vibrate(parent.playernum, 1, 30 - (100 / zsp));
            }
        }
        landing_anim = 11;
    }
    zsp = 0;
    inair = false;
    grav = 0;
    hang_time = 0;
}

function set_player_finish()
{
    autopilot = true;
    finish = true;
    if (obj_track.rally && playernum >= 0)
    {
        obj_main.camera[view_num].obj.mode = 13;
    }
    if (play_brake)
    {
        play_brake = false;
        audio_stop_sound(parent.sndBrake);
        audio_stop_sound(parent.brake_multi);
    }
}

function is_onground(arg0, arg1)
{
    if (abs(xoff) > (arg0[10] / 2) || arg0[4] == 256)
    {
        return false;
    }
    var ty = lerp(arg0[2] + lengthdir_y(xoff, arg0[11]), arg1[2] + lengthdir_y(xoff, arg1[11]), yoff / obj_track.sep);
    return z >= (ty - obj_track.seg) && z < (ty + obj_track.seg);
}

function set_z_position(arg0, arg1)
{
    z = lerp(arg0[2] + lengthdir_y(xoff, arg0[11]), arg1[2] + lengthdir_y(xoff, arg1[11]), yoff / obj_track.sep) - obj_track.seg;
}

function play_drift_sound()
{
    if (obj_main.players < 2)
    {
        if (audio_emitter_exists(other.sfxEmit))
        {
            audio_stop_sound(other.sndDrift);
            other.sndDrift = audio_play_sound_on(other.sfxEmit, snd_drift, true, other.playernum + 20);
        }
    }
    else
    {
        audio_stop_sound(other.drift_multi);
        other.drift_multi = audio_play_sound(snd_drift, other.playernum + 20, 1, obj_main.sfxVolume);
    }
}

function play_brake_sound()
{
    if (obj_main.players < 2)
    {
        if (audio_emitter_exists(other.sfxEmit))
        {
            audio_stop_sound(other.sndBrake);
            other.sndBrake = audio_play_sound_on(other.sfxEmit, snd_braking, true, other.playernum + 20);
        }
    }
    else
    {
        audio_stop_sound(other.brake_multi);
        other.brake_multi = audio_play_sound(snd_braking, other.playernum + 20, 1, obj_main.sfxVolume);
    }
}

function car_crash_out()
{
    if (!inv)
    {
        if (playernum >= 0)
        {
        }
        if (!crash)
        {
            if (playernum >= 0 && !parent.ghost)
            {
                sfx_play(snd_bigCrash, 0, 0);
                var _cam = obj_main.camera[view_num];
                _cam.shake = 50;
                _cam.obj.mode = 5;
                _cam.obj.x_start = _cam.cam.x;
                _cam.obj.y_start = _cam.cam.y;
                _cam.obj.z_start = _cam.cam.z;
                _cam.obj.yaw_start = _cam.cam.yaw;
            }
            crash = 1000;
            crash_timer = 40;
            if (play_drift)
            {
                audio_stop_sound(parent.sndDrift);
                audio_stop_sound(parent.drift_multi);
                audio_stop_sound(parent.sndBoost);
                superdrift = 1;
                play_drift = false;
            }
            drifttime = 0;
            brakedriftgrip = 0;
            z = 0;
            for (var i = 0; i < 4; i++)
            {
                var ctdir = facedir + (i * 90) + 45;
                instance_create_depth(x + lengthdir_x(4, ctdir), y + lengthdir_y(4, ctdir), parent.depth, obj_crash_tire, 
                {
                    z: z - 8,
                    xsp: lengthdir_x(1, ctdir),
                    ysp: lengthdir_y(1, ctdir)
                });
            }
            repeat (20)
            {
                instance_create_depth(x + random_range(-32, 32), y + random_range(-32, 32), parent.depth, obj_bang, 
                {
                    z: z + random_range(-48, -16),
                    image_index: random(1)
                });
            }
            zsp *= 4;
        }
        grav = 0.6;
        z = 0;
        zsp = -zsp * 0.5;
    }
    achievement_set(obj_main.achievement_list_backmarker);
}
