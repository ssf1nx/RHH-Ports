function bookkeeping_update_finishes(arg0)
{
    var _place = event_check_type(15) ? (4 - add_bits(obj_race_manager.event_medal)) : arg0.place;
    if (_place < 4)
    {
        obj_main.char_firsts[obj_main.car_data[0].index]++;
        obj_main.total_podium++;
    }
    {
    }
    achievement_set(obj_main.achievement_list_winners);
}
