import { RhythmRenderer } from './rhythm-core.js';

class PulseProcessor extends AudioWorkletProcessor {
  constructor() {
    super(); this.engine=new RhythmRenderer(sampleRate); this.playing=false; this.reportFrame=0;
    this.port.onmessage=({data})=>{
      if(data.type==='start'){this.engine.configure(data.config);this.playing=true;this.reportFrame=0;}
      if(data.type==='stop'){this.playing=false;}
      if(data.type==='volume'){this.engine.c.volume=Math.max(0,Math.min(1,data.value));}
    };
  }
  process(_inputs,outputs) {
    const output=outputs[0][0];
    if(this.playing){
      this.engine.render(output);
      if(this.engine.frame-this.reportFrame>sampleRate/20){
        this.reportFrame=this.engine.frame;
        this.port.postMessage({seconds:this.engine.seconds,bpm:this.engine.activeBpm,bar:this.engine.activeBar,beat:this.engine.activeBeat});
      }
    }else output.fill(0);
    return true;
  }
}
registerProcessor('pulse-clock',PulseProcessor);
