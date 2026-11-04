(() => {
  let context, node, ready, revision=0;
  const state={running:false,seconds:0,bpm:96,bar:0,beat:0,error:''};
  async function ensureAudio(){
    if(!context){context=new AudioContext({latencyHint:'interactive'});}
    await context.resume();
    if(!ready) ready=context.audioWorklet.addModule('./rhythm-worklet.js').then(()=>{
      node=new AudioWorkletNode(context,'pulse-clock',{numberOfInputs:0,numberOfOutputs:1,outputChannelCount:[1]});
      node.port.onmessage=({data})=>{state.seconds=data.seconds;state.bpm=data.bpm;state.bar=data.bar;state.beat=data.beat;};
      node.connect(context.destination);
      context.onstatechange=()=>{if(context.state==='suspended'&&state.running){state.error='Audio paused by browser. Tap Start to resume.';state.running=false;}};
    });
    return ready;
  }
  window.PulseAudio={
    start(config){
      const request=++revision;state.error='';state.seconds=0;state.bpm=config.bpm;state.bar=0;state.beat=0;state.running=true;
      ensureAudio().then(()=>{if(request===revision)node.port.postMessage({type:'start',config});})
        .catch(error=>{if(request!==revision)return;ready=null;state.running=false;state.error='Audio could not start: '+error.message;});
    },
    stop(){revision++;state.running=false;if(node)node.port.postMessage({type:'stop'});},
    volume(value){if(node)node.port.postMessage({type:'volume',value});},
    status(){return JSON.stringify(state);}
  };
})();
