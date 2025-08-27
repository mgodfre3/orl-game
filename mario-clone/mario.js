// Simple Mario clone logic (placeholder)
const canvas = document.getElementById('gameCanvas');
const ctx = canvas.getContext('2d');

let mario = { x: 50, y: 300, w: 40, h: 40, vy: 0, jumping: false };
let gravity = 1.5;
let ground = 340;

function drawMario() {
  ctx.fillStyle = '#e63946';
  ctx.fillRect(mario.x, mario.y, mario.w, mario.h);
}

function clear() {
  ctx.clearRect(0, 0, canvas.width, canvas.height);
}

function update() {
  if (mario.jumping) {
    mario.vy += gravity;
    mario.y += mario.vy;
    if (mario.y >= ground) {
      mario.y = ground;
      mario.jumping = false;
      mario.vy = 0;
    }
  }
}

function loop() {
  clear();
  update();
  drawMario();
  requestAnimationFrame(loop);
}

window.addEventListener('keydown', (e) => {
  if (e.code === 'Space' && !mario.jumping) {
    mario.jumping = true;
    mario.vy = -20;
  }
});

loop();
