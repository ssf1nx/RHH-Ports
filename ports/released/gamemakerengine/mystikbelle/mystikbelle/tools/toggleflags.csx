#r "UndertaleModLib.dll"
using System;
using System.Linq;
using System.Collections.Generic;
using UndertaleModLib;
using UndertaleModLib.Models;

EnsureDataLoaded();

var gi = Data.GeneralInfo;

var setStr   = Environment.GetEnvironmentVariable("SET_FLAGS")   ?? "";
var clearStr = Environment.GetEnvironmentVariable("CLEAR_FLAGS") ?? "";

static IEnumerable<string> SplitFlags(string s) =>
    string.IsNullOrWhiteSpace(s)
        ? Enumerable.Empty<string>()
        : s.Split(new[] { ',', ';', ' ', '\t', '\n', '\r' }, StringSplitOptions.RemoveEmptyEntries)
           .Select(x => x.Trim());

static bool TryParseFlag(string name, out UndertaleGeneralInfo.InfoFlags flag)
{
    if (Enum.TryParse(name, true, out flag))
        return true;

    var map = new Dictionary<string, UndertaleGeneralInfo.InfoFlags>(StringComparer.OrdinalIgnoreCase);
    return map.TryGetValue(name, out flag);
}

var toSet = SplitFlags(setStr).Select(n => TryParseFlag(n, out var f) ? f : (UndertaleGeneralInfo.InfoFlags?)null).Where(f => f.HasValue).Select(f => f.Value).ToList();
var toClr = SplitFlags(clearStr).Select(n => TryParseFlag(n, out var f) ? f : (UndertaleGeneralInfo.InfoFlags?)null).Where(f => f.HasValue).Select(f => f.Value).ToList();

UndertaleGeneralInfo.InfoFlags setMask = toSet.Aggregate((UndertaleGeneralInfo.InfoFlags)0, (acc, f) => acc | f);
UndertaleGeneralInfo.InfoFlags clrMask = toClr.Aggregate((UndertaleGeneralInfo.InfoFlags)0, (acc, f) => acc | f);

var before = gi.Info;
gi.Info = (before | setMask) & ~clrMask;

string FlagsToNames(UndertaleGeneralInfo.InfoFlags v) =>
    string.Join(", ", Enum.GetValues(typeof(UndertaleGeneralInfo.InfoFlags))
        .Cast<UndertaleGeneralInfo.InfoFlags>()
        .Where(f => f != 0 && v.HasFlag(f)));

ScriptMessage($"[INFO] InfoFlags BEFORE: {before}");
ScriptMessage($"[INFO] InfoFlags AFTER : {gi.Info}");
