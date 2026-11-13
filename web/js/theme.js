// THEME LOGIC
// Switches between HyperCode Store (Dark) and EdClub (Light) with a fade transition

function initTheme() {
  const savedTheme = localStorage.getItem('forest_theme') || 'dark';
  if (savedTheme === 'light') {
    document.body.classList.add('light-mode');
  }
  updateThemeIcon(savedTheme);
}

function updateThemeIcon(theme) {
  const moonIcon = document.getElementById('icon-moon');
  const sunIcon = document.getElementById('icon-sun');
  if (!moonIcon || !sunIcon) return;

  // Icon represents CURRENT state: Light mode = Sun, Dark mode = Moon
  if (theme === 'light') {
    sunIcon.style.display = 'block';
    moonIcon.style.display = 'none';
  } else {
    moonIcon.style.display = 'block';
    sunIcon.style.display = 'none';
  }
}

function toggleTheme(e) {
  if (e) e.preventDefault();
  
  const isLight = document.body.classList.contains('light-mode');
  const newTheme = isLight ? 'dark' : 'light';
  
  if (isLight) {
    document.body.classList.remove('light-mode');
  } else {
    document.body.classList.add('light-mode');
  }
  
  localStorage.setItem('forest_theme', newTheme);
  updateThemeIcon(newTheme);
}

// Initialize immediately
document.addEventListener('DOMContentLoaded', initTheme);
