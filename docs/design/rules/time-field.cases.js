var TIME_CASES_MINUTES = [
  [{h12:12, min:0,  pm:false}, 0,    "midnight is 12 AM and is zero, the case every 12 hour clock gets wrong"],
  [{h12:12, min:0,  pm:true},  720,  "noon is 12 PM and is 720, the other one it gets wrong"],
  [{h12:12, min:30, pm:false}, 30,   "half past midnight"],
  [{h12:1,  min:0,  pm:false}, 60,   "1 AM"],
  [{h12:7,  min:30, pm:true},  1170, "an ordinary evening call"],
  [{h12:11, min:59, pm:true},  1439, "the last minute of the day"],
  [{h12:9,  min:5,  pm:false}, 545,  "single digit minutes"]
];

var TIME_CASES_BUMP = [
  [{h12:12, min:0,  pm:false}, "hour", 1,  {h12:1,  min:0,  pm:false}, "the hour wraps 12 to 1, not to 13"],
  [{h12:1,  min:0,  pm:false}, "hour", -1, {h12:12, min:0,  pm:false}, "and back from 1 to 12"],
  [{h12:7,  min:59, pm:true},  "min",  1,  {h12:7,  min:0,  pm:true},  "the minutes wrap to 00 and DO NOT carry into the hour"],
  [{h12:7,  min:0,  pm:true},  "min",  -1, {h12:7,  min:59, pm:true},  "and back, still without touching the hour"],
  [{h12:7,  min:30, pm:true},  "mer",  1,  {h12:7,  min:30, pm:false}, "the meridiem toggles"],
  [{h12:7,  min:30, pm:false}, "mer",  -1, {h12:7,  min:30, pm:true},  "either way"]
];

function runTimeFieldTests() {
  var failures = [];
  TIME_CASES_MINUTES.forEach(function (c) {
    var got = timeToMinutes(c[0]);
    if (got !== c[1]) failures.push(c[2] + ": " + formatTime(c[0]) + " gave " + got + ", expected " + c[1]);
    /* and it must survive the round trip, or the control cannot show back what
       it was given */
    var back = minutesToTime(c[1]);
    if (formatTime(back) !== formatTime(c[0]))
      failures.push(c[2] + ": " + c[1] + " came back as " + formatTime(back) + ", expected " + formatTime(c[0]));
  });
  TIME_CASES_BUMP.forEach(function (c) {
    var got = bumpTime(c[0], c[1], c[2]);
    if (formatTime(got) !== formatTime(c[3]))
      failures.push(c[4] + ": got " + formatTime(got) + ", expected " + formatTime(c[3]));
  });
  /* Every minute of the day survives the round trip, which no hand written list
     of cases would cover. */
  for (var m = 0; m < 1440; m++) {
    if (timeToMinutes(minutesToTime(m)) !== m) {
      failures.push("minute " + m + " does not survive the round trip");
      break;
    }
  }
  return { ran: TIME_CASES_MINUTES.length + TIME_CASES_BUMP.length + 1, failures: failures };
}
