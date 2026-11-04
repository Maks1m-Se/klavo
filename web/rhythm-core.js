// Audio clock only: no DOM, timers, dates or rendering dependencies.
export class RhythmRenderer {
  constructor(sampleRate = 48000) {
    this.sampleRate = sampleRate;
    this.voices = Array.from({length: 24}, () => ({age: -1, freq: 0, gain: 0, sound: 0}));
    this.configure({});
  }
  configure(input = {}) {
    const clamp = (x,a,b,f) => Number.isFinite(+x) ? Math.max(a, Math.min(b,+x)) : f;
    this.c = {
      bpm: clamp(input.bpm,20,300,96), beats: Math.round(clamp(input.beats,1,12,4)),
      subdivision: Math.round(clamp(input.subdivision,1,8,1)),
      accents: Array.isArray(input.accents) ? input.accents : [2,1,1,1],
      volume: clamp(input.volume,0,1,.6), sound: Math.round(clamp(input.sound,0,2,0)),
      swing: clamp(input.swing,.5,.75,.5),
      audibleBars: Math.round(clamp(input.audibleBars,1,32,4)),
      silentBars: Math.round(clamp(input.silentBars,0,32,0)),
      poly: Math.round(clamp(input.poly,0,12,0)),
      rampStep: clamp(input.rampStep,0,40,0), rampEvery: Math.round(clamp(input.rampEvery,1,64,8)),
      targetBpm: clamp(input.targetBpm,20,300,120)
    };
    this.bpm = this.c.bpm; this.frame = 0; this.nextStep = 0; this.nextPoly = 0;
    this.sub = 0; this.beat = 0; this.bar = 0; this.activeBar = 0; this.activeBeat = 0; this.activeBpm = this.bpm;
    this.voices.forEach(v => v.age = -1);
  }
  trigger(accent, subdivision = false, secondary = false) {
    if (!accent) return;
    if (subdivision) accent = 1;
    const voice = this.voices.find(v => v.age < 0) || this.voices[0];
    voice.age = 0; voice.sound = this.c.sound;
    voice.freq = secondary ? 720 : accent === 2 ? 1560 : subdivision ? 1120 : 1200;
    voice.gain = secondary ? .24 : subdivision ? .13 : accent === 2 ? .40 : .29;
  }
  render(output, onEvent = null) {
    const sr = this.sampleRate, c = this.c;
    for (let i=0;i<output.length;i++,this.frame++) {
      if (this.frame >= Math.round(this.nextStep)) {
        const silent = c.silentBars > 0 && this.bar % (c.audibleBars+c.silentBars) >= c.audibleBars;
        const accent = c.accents[this.beat % c.accents.length] ?? 1;
        if (!silent) this.trigger(accent, this.sub > 0);
        if (onEvent) onEvent({frame:this.frame,beat:this.beat,sub:this.sub,bar:this.bar,bpm:this.bpm,silent});
        this.activeBar = this.bar; this.activeBeat = this.beat; this.activeBpm = this.bpm;
        let fraction = 1/c.subdivision;
        if (c.subdivision === 2) fraction = this.sub === 0 ? c.swing : 1-c.swing;
        this.nextStep += sr * 60/this.bpm * fraction;
        this.sub++;
        if (this.sub >= c.subdivision) {
          this.sub=0; this.beat++;
          if (this.beat>=c.beats) {
            this.beat=0; this.bar++;
            if(c.rampStep>0 && this.bar%c.rampEvery===0) this.bpm=Math.min(c.targetBpm,this.bpm+c.rampStep);
          }
        }
      }
      if(c.poly>0 && this.frame >= Math.round(this.nextPoly)) {
        const silent=c.silentBars>0 && this.activeBar%(c.audibleBars+c.silentBars)>=c.audibleBars;
        if(!silent) this.trigger(1,false,true);
        this.nextPoly += sr*60/this.activeBpm*c.beats/c.poly;
      }
      let sample = 0;
      for(const v of this.voices) {
        if(v.age<0) continue;
        const t=v.age/sr;
        if(t>=.045) {v.age=-1;continue;}
        const attack=Math.min(1,t/.0012), tail=Math.min(1,(.045-t)/.006);
        const decay=Math.exp(-t/(v.sound===1?.006:.009));
        let wave;
        if(v.sound===2) wave=Math.sin(2*Math.PI*v.freq*t);
        else if(v.sound===1) wave=Math.sin(2*Math.PI*v.freq*.7*t);
        else wave=.78*Math.sin(2*Math.PI*v.freq*t)+.22*Math.sin(2*Math.PI*v.freq*1.63*t);
        sample += wave*attack*tail*decay*v.gain;
        v.age++;
      }
      output[i]=Math.max(-1,Math.min(1,sample*c.volume));
    }
  }
  get seconds() {return this.frame/this.sampleRate;}
}
