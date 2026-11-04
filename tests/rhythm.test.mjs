import assert from 'node:assert/strict';
import { RhythmRenderer } from '../web/rhythm-core.js';

function events(config, seconds, sr=48000) {
 const r=new RhythmRenderer(sr);r.configure(config);const hits=[];
 const out=new Float32Array(Math.ceil(seconds*sr));r.render(out,e=>hits.push(e));
 assert(out.every(Number.isFinite));assert(out.every(v=>Math.abs(v)<=1));
 return {r,hits,out};
}
// Fractional beat periods retain phase; they do not round each interval.
for(const bpm of [20,96,137,300]){
 const {hits}=events({bpm,subdivision:4},15);
 for(let i=0;i<hits.length;i++)assert(Math.abs(hits[i].frame-i*48000*60/bpm/4)<=.51);
}
const gap=events({bpm:120,beats:4,audibleBars:1,silentBars:1},4);
assert(gap.hits.filter(e=>e.bar===0).every(e=>!e.silent));
assert(gap.hits.filter(e=>e.bar===1).every(e=>e.silent));
assert(gap.out.slice(2*48000+3000).every(v=>v===0));
const swing=events({bpm:120,beats:4,subdivision:2,swing:2/3},2).hits;
assert.equal(swing[1].frame,16000);assert.equal(swing[2].frame,24000);
const ramp=events({bpm:100,beats:2,rampStep:10,rampEvery:1,targetBpm:120},8).hits;
assert.equal(ramp.find(e=>e.bar===1).bpm,110);assert.equal(ramp.find(e=>e.bar===2).bpm,120);
assert(ramp.every(e=>e.bpm<=120));
const {out}=events({bpm:96,beats:2,poly:3},2);
assert(out.some(v=>Math.abs(v)>.01));
console.log('Passed: fractional scheduling, 20–300 BPM, subdivisions, gap silence, swing, tempo ramp, finite bounded PCM.');
