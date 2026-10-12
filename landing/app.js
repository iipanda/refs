'use strict';
const demo = document.querySelector('.demo');
const tabs = [...document.querySelectorAll('[role="tab"]')];
const panels = [...document.querySelectorAll('[data-panel]')];
const capture = document.querySelector('.capture-target');
const saved = document.querySelector('.saved-preview');
const noteInput = document.querySelector('#reference-note');
const counter = document.querySelector('#note-count');
const copyButton = document.querySelector('#copy-reference');
const copyStatus = document.querySelector('#copy-status');
const initialNote = 'The quiet colors and generous space around a single object.';
let savedNote = initialNote;
function updateCount(){ counter.textContent = `${noteInput.value.length} / 180`; }
function updateReference(){
  document.querySelector('#saved-note').textContent = savedNote;
  document.querySelector('#reference-text').textContent = `Reference: Studio detail\nSource: forme.example\nWhat I like: ${savedNote}`;
}
function selectStep(step, focusTab = false){
  demo.dataset.step = String(step);
  tabs.forEach((tab,index) => {
    tab.setAttribute('aria-selected', String(index === step));
    tab.tabIndex = index === step ? 0 : -1;
  });
  panels.forEach(panel => { panel.hidden = Number(panel.dataset.panel) !== step; });
  document.querySelector('#demo-panel').setAttribute('aria-labelledby',tabs[step].id);
  capture.hidden = step !== 0;
  saved.hidden = step === 0;
  if(step === 1) savedNote = noteInput.value.trim() || initialNote;
  if(step === 2) savedNote = noteInput.value.trim() || initialNote;
  updateReference();
  copyStatus.textContent = '';
  copyButton.firstChild.textContent = 'Copy reference ';
  if(focusTab) tabs[step].focus({preventScroll:true});
}
tabs.forEach((tab,index)=>{
  tab.addEventListener('click',()=>selectStep(index));
  tab.addEventListener('keydown',event=>{
    let next;
    if(event.key === 'ArrowRight') next = (index + 1) % tabs.length;
    if(event.key === 'ArrowLeft') next = (index + tabs.length - 1) % tabs.length;
    if(event.key === 'Home') next = 0;
    if(event.key === 'End') next = tabs.length - 1;
    if(next !== undefined){event.preventDefault();selectStep(next,true);}
  });
});
document.querySelector('#capture-button').addEventListener('click',()=>{
  selectStep(1);
  noteInput.focus({preventScroll:true});
});
noteInput.addEventListener('input',()=>{
  updateCount();
  savedNote = noteInput.value.trim() || initialNote;
  updateReference();
});
document.querySelector('#note-form').addEventListener('submit',event=>{
  event.preventDefault();
  if(!noteInput.value.trim()){
    noteInput.setCustomValidity('Add a short note about the detail you like.');
    noteInput.reportValidity();
    noteInput.addEventListener('input',()=>noteInput.setCustomValidity(''),{once:true});
    return;
  }
  selectStep(2);
  copyButton.focus({preventScroll:true});
});
document.querySelector('#reset-demo').addEventListener('click',()=>{
  noteInput.value = initialNote;
  noteInput.setCustomValidity('');
  savedNote = initialNote;
  updateCount();
  selectStep(0);
});
async function copyText(text, status){
  try{
    await navigator.clipboard.writeText(text);
    status.textContent = 'Copied. Ready for your next brief.';
    return true;
  }catch{
    status.textContent = 'Clipboard access is unavailable. Select and copy the text above.';
    return false;
  }
}
copyButton.addEventListener('click',async()=>{
  const success = await copyText(document.querySelector('#reference-text').textContent,copyStatus);
  if(success) copyButton.firstChild.textContent = 'Reference copied ';
});
document.querySelector('#copy-setup').addEventListener('click',async()=>{
  const status = document.querySelector('#setup-status');
  const success = await copyText(document.querySelector('.setup-code code').textContent,status);
  if(success) status.textContent = 'Command copied. Run it in your terminal to connect Claude Code.';
});
const motionButton = document.querySelector('#motion-button');
let motionTimer;
motionButton.addEventListener('click',()=>{
  const piece = document.querySelector('.ref-motion');
  if(piece.classList.contains('is-playing')) return;
  piece.classList.add('is-playing');
  motionButton.setAttribute('aria-label','Sample interaction playing');
  clearTimeout(motionTimer);
  motionTimer = setTimeout(()=>{
    piece.classList.remove('is-playing');
    motionButton.setAttribute('aria-label','Play the sample interaction');
  },1200);
});
window.addEventListener('pagehide',()=>{clearTimeout(motionTimer);});
updateCount();updateReference();
