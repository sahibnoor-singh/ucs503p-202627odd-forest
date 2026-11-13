// =============================================
// ADMIN.JS — Handles login, upload, and publishing
// =============================================

let selectedFiles = [];

// ---- CHECK IF ALREADY LOGGED IN ----
window.addEventListener('DOMContentLoaded', () => {
  const token = localStorage.getItem('forest_token');
  if (token) {
    showUploadDashboard();
    loadVersionHistory();
  }
  // Set today's date as default
  document.getElementById('date').valueAsDate = new Date();
});

// ---- LOGIN ----
async function handleLogin() {
  const username = document.getElementById('username').value;
  const password = document.getElementById('password').value;

  if (!username || !password) {
    showAlert('login-alert', 'Please enter username and password.', 'error');
    return;
  }

  try {
    const res = await fetch(`${API_BASE_URL}/api/auth/login`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ username, password })
    });

    const data = await res.json();

    if (!res.ok) {
      showAlert('login-alert', data.error || 'Login failed', 'error');
      return;
    }

    // Save token and switch to upload dashboard
    localStorage.setItem('forest_token', data.token);
    showUploadDashboard();
    loadVersionHistory();

  } catch (err) {
    showAlert('login-alert', 'Could not connect to backend. Is it running?', 'error');
  }
}

// ---- LOGOUT ----
function handleLogout() {
  localStorage.removeItem('forest_token');
  document.getElementById('login-section').style.display = 'block';
  document.getElementById('upload-section').style.display = 'none';
}

function showUploadDashboard() {
  document.getElementById('login-section').style.display = 'none';
  document.getElementById('upload-section').style.display = 'block';
}

// ---- DRAG & DROP ----
const dropzone = document.getElementById('dropzone');

dropzone.addEventListener('dragover', (e) => {
  e.preventDefault();
  dropzone.classList.add('dragover');
});

dropzone.addEventListener('dragleave', () => {
  dropzone.classList.remove('dragover');
});

dropzone.addEventListener('drop', (e) => {
  e.preventDefault();
  dropzone.classList.remove('dragover');
  const files = Array.from(e.dataTransfer.files);
  addFiles(files);
});

// ---- FILE SELECT (browse button) ----
function handleFileSelect(event) {
  const files = Array.from(event.target.files);
  addFiles(files);
}

function addFiles(files) {
  selectedFiles = [...selectedFiles, ...files];
  renderFileList();
}

function removeFile(index) {
  selectedFiles.splice(index, 1);
  renderFileList();
}

function renderFileList() {
  const list = document.getElementById('fileList');
  if (selectedFiles.length === 0) {
    list.innerHTML = '';
    return;
  }
  list.innerHTML = selectedFiles.map((f, i) => `
    <li>
      <span>${escapeHtml(f.name)}</span>
      <span>
        <span class="file-size">${formatFileSize(f.size)}</span>
        <button onclick="removeFile(${i})" style="background: none; border: none; color: var(--accent-red); cursor: pointer; margin-left: 0.5rem; font-size: 1rem;">✕</button>
      </span>
    </li>
  `).join('');
}

// ---- UPLOAD ----
async function handleUpload() {
  const btn = document.querySelector('button[onclick="handleUpload()"]');
  const originalText = btn.innerText;
  
  const token = localStorage.getItem('forest_token');
  const title = document.getElementById('title').value;
  const deliverableType = document.getElementById('deliverableType').value;
  const version = document.getElementById('version').value;
  const date = document.getElementById('date').value;
  const changeSummary = document.getElementById('changeSummary').value;

  // Validate
  if (!title || !version || !date) {
    showAlert('upload-alert', 'Please fill in Title, Version, and Date.', 'error');
    return;
  }
  if (selectedFiles.length === 0) {
    showAlert('upload-alert', 'Please select at least one file to upload.', 'error');
    return;
  }

  btn.disabled = true;
  btn.innerText = 'Processing...';

  // Build FormData (like multipart/form-data in Spring)
  const formData = new FormData();
  formData.append('title', title);
  formData.append('deliverableType', deliverableType);
  formData.append('version', version);
  formData.append('date', date);
  formData.append('changeSummary', changeSummary);
  selectedFiles.forEach(f => formData.append('files', f));

  try {
    const res = await fetch(`${API_BASE_URL}/api/uploads`, {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${token}` },
      body: formData
    });

    const data = await res.json();

    if (!res.ok) {
      if (res.status === 401) {
        handleLogout();
        showAlert('login-alert', 'Session expired. Please log in again to upload.', 'error');
        return;
      }
      showAlert('upload-alert', data.error || 'Upload failed', 'error');
      return;
    }

    showAlert('upload-alert', `"${title}" uploaded successfully! You can now publish it.`, 'success');

    // Clear form
    selectedFiles = [];
    renderFileList();
    document.getElementById('title').value = '';
    document.getElementById('version').value = '';
    document.getElementById('changeSummary').value = '';

    // Reload version history
    loadVersionHistory();

  } catch (err) {
    showAlert('upload-alert', 'Server appears to be down or offline. Please wait while it is being corrected.', 'error');
  } finally {
    btn.disabled = false;
    btn.innerText = originalText;
  }
}

// ---- VERSION HISTORY ----
async function loadVersionHistory() {
  try {
    const res = await fetch(`${API_BASE_URL}/api/uploads`);
    const uploads = await res.json();
    const container = document.getElementById('versionHistory');

    if (uploads.length === 0) {
      container.innerHTML = '<p style="color: var(--text-muted);">No uploads yet.</p>';
      return;
    }

    container.innerHTML = uploads.map(upload => {
      const files = parseFiles(upload.files);
      const isPublished = upload.published === 1;
      const fileLinks = files.map(file =>
        `<a href="${escapeHtml(downloadUrl(file.url))}" target="_blank" rel="noopener" style="font-size: 0.8rem; margin-right: 0.5rem;">${escapeHtml(file.originalName)}</a>`
      ).join('');

      return `
        <div class="version-item">
          <div class="version-info">
            <h4>${escapeHtml(upload.title)}</h4>
            <span class="version-meta">
              v${escapeHtml(upload.version)} • ${escapeHtml(upload.date)} • ${escapeHtml(upload.deliverable_type)} • Uploaded by: ${escapeHtml(upload.author || 'System')}
              ${isPublished ? ' • <span style="color: var(--accent-green);">✓ Published</span>' : ''}
            </span>
            ${upload.change_summary ? `<p style="color: var(--text-muted); font-size: 0.8rem; margin-top: 0.3rem;">${escapeHtml(upload.change_summary)}</p>` : ''}
            <div style="margin-top: 0.3rem;">
              ${fileLinks}
            </div>
          </div>
          <div style="display: flex; gap: 0.5rem; align-items: center;">
            <button class="btn btn-outline" style="font-size: 0.8rem; padding: 0.4rem 0.8rem;" onclick="openEditModal(this)" data-id="${escapeHtml(upload.id)}" data-title="${escapeHtml(upload.title)}" data-type="${escapeHtml(upload.deliverable_type)}" data-version="${escapeHtml(upload.version)}" data-date="${escapeHtml(upload.date)}" data-summary="${escapeHtml(upload.change_summary || '')}">Edit</button>
            <button class="btn btn-outline" style="font-size: 0.8rem; padding: 0.4rem 0.8rem; color: var(--accent-red); border-color: var(--accent-red);" onclick="deleteItem(this.dataset.id, this)" data-id="${escapeHtml(upload.id)}">Delete</button>
            ${!isPublished ? `<button class="btn btn-primary" style="font-size: 0.8rem; padding: 0.4rem 0.8rem;" onclick="publishItem(this.dataset.id, this)" data-id="${escapeHtml(upload.id)}">Publish</button>` : ''}
          </div>
        </div>
      `;
    }).join('');

  } catch (err) {
    document.getElementById('versionHistory').innerHTML =
      '<p style="color: var(--accent-red);">Could not load history.</p>';
  }
}

// ---- EDIT & DELETE ----
async function deleteItem(id, btn) {
  if (!confirm("Are you sure you want to permanently delete this presentation? This will delete the files as well.")) {
    return;
  }
  let originalText = '';
  if (btn) {
    originalText = btn.innerText;
    btn.disabled = true;
    btn.innerText = 'Deleting...';
  }

  const token = localStorage.getItem('forest_token');
  try {
    const res = await fetch(`${API_BASE_URL}/api/uploads/${id}`, {
      method: 'DELETE',
      headers: { 'Authorization': `Bearer ${token}` }
    });
    if (res.ok) {
      showAlert('upload-alert', 'Deleted successfully!', 'success');
      loadVersionHistory();
    } else {
      const data = await res.json().catch(() => ({}));
      if (res.status === 401) {
        handleLogout();
        showAlert('login-alert', 'Session expired. Please log in again.', 'error');
      } else {
        showAlert('upload-alert', data.error || 'Delete failed', 'error');
      }
    }
  } catch (err) {
    showAlert('upload-alert', 'Server appears to be down or offline. Please wait while it is being corrected.', 'error');
  } finally {
    if (btn) {
      btn.disabled = false;
      btn.innerText = originalText;
    }
  }
}

function openEditModal(button) {
  const { id, title, type, version, date, summary } = button.dataset;
  document.getElementById('edit-id').value = id;
  document.getElementById('edit-title').value = title;
  document.getElementById('edit-deliverableType').value = type;
  document.getElementById('edit-version').value = version;
  document.getElementById('edit-date').value = date;
  document.getElementById('edit-changeSummary').value = summary;
  document.getElementById('edit-modal').style.display = 'flex';
}

function closeEditModal() {
  document.getElementById('edit-modal').style.display = 'none';
}

async function submitEdit() {
  const id = document.getElementById('edit-id').value;
  const token = localStorage.getItem('forest_token');
  const formData = new FormData();
  formData.append('title', document.getElementById('edit-title').value);
  formData.append('deliverableType', document.getElementById('edit-deliverableType').value);
  formData.append('version', document.getElementById('edit-version').value);
  formData.append('date', document.getElementById('edit-date').value);
  formData.append('changeSummary', document.getElementById('edit-changeSummary').value);

  const fileInput = document.getElementById('edit-file');
  Array.from(fileInput.files).forEach(file => formData.append('files', file));

  // Show processing
  const saveBtn = document.querySelector('#edit-modal .btn-primary');
  const oldText = saveBtn.innerText;
  saveBtn.innerText = 'Processing...';
  saveBtn.disabled = true;
  showAlert('upload-alert', 'Saving changes…', 'info', 1800);

  try {
    const res = await fetch(`${API_BASE_URL}/api/uploads/${id}`, {
      method: 'PUT',
      headers: { 
        'Authorization': `Bearer ${token}`
      },
      body: formData
    });
    const data = await readResponse(res);
    if (res.ok) {
      showAlert('upload-alert', 'Updated successfully!', 'success');
      closeEditModal();
      loadVersionHistory();
    } else {
      if (res.status === 401) {
        closeEditModal();
        handleLogout();
        showAlert('login-alert', 'Session expired. Please log in again.', 'error');
      } else {
        showAlert('upload-alert', data.error || 'Update failed', 'error');
      }
    }
  } catch (err) {
    showAlert('upload-alert', 'Update failed. Check connection.', 'error');
  } finally {
    saveBtn.innerText = oldText;
    saveBtn.disabled = false;
  }
}

// ---- PUBLISH ----
async function publishItem(id, btn) {
  let originalText = '';
  if (btn) {
    originalText = btn.innerText;
    btn.disabled = true;
    btn.innerText = 'Publishing...';
  }

  const token = localStorage.getItem('forest_token');
  try {
    const res = await fetch(`${API_BASE_URL}/api/uploads/${id}/publish`, {
      method: 'POST',
      headers: { 'Authorization': `Bearer ${token}` }
    });

    if (res.ok) {
      showAlert('upload-alert', 'Published successfully!', 'success');
      loadVersionHistory();
    } else {
      const data = await res.json().catch(() => ({}));
      if (res.status === 401) {
        showAlert('upload-alert', 'Session expired. Please logout and login again.', 'error');
      } else {
        showAlert('upload-alert', data.error || 'Publish failed', 'error');
      }
    }
  } catch (err) {
    showAlert('upload-alert', 'Server appears to be down or offline. Please wait while it is being corrected.', 'error');
  } finally {
    if (btn) {
      btn.disabled = false;
      btn.innerText = originalText;
    }
  }
}

// ---- HELPERS ----
async function readResponse(response) {
  const body = await response.text();
  try { return JSON.parse(body); } catch (_) { return { error: body || `Request failed (${response.status})` }; }
}

function showAlert(containerId, message, type, duration = 4000) {
  const container = document.getElementById('toast-container');
  if (!container) return;
  const toast = document.createElement('div');
  toast.className = `toast toast-${type}`;
  toast.textContent = message;
  container.appendChild(toast);
  setTimeout(() => {
    toast.classList.add('fade-out');
    toast.addEventListener('animationend', () => toast.remove());
  }, duration);
}

function escapeHtml(value) {
  return String(value ?? '').replace(/[&<>"']/g, character => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
  }[character]));
}

function parseFiles(value) {
  try {
    const files = JSON.parse(value || '[]');
    return Array.isArray(files) ? files : [];
  } catch (_) {
    return [];
  }
}

function downloadUrl(fileUrl) {
  const path = String(fileUrl || '');
  return path.startsWith('/uploads/') ? `${API_BASE_URL}${encodeURI(path)}` : '#';
}

function formatFileSize(bytes) {
  if (bytes < 1024) return bytes + ' B';
  if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB';
  return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
}

// ---- SETTINGS ----
async function loadCurrentPhase() {
  try {
    const res = await fetch(`${API_BASE_URL}/api/settings/phase`);
    if (res.ok) {
      const data = await res.json();
      const select = document.getElementById('currentPhase');
      if (select) {
        select.value = data.phase;
      }
    }
  } catch (err) {
    console.error("Could not load current phase", err);
  }
}

async function handlePhaseChange() {
  const phase = document.getElementById('currentPhase').value;
  const token = localStorage.getItem('forest_token');
  if (!token) {
    showAlert('upload-alert', 'Session expired. Please logout and login again.', 'error');
    return;
  }
  try {
    const res = await fetch(`${API_BASE_URL}/api/settings/phase`, {
      method: 'PUT',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${token}`
      },
      body: JSON.stringify({ phase })
    });
    const data = await res.json().catch(() => ({}));
    if (res.ok) {
      showAlert('upload-alert', 'Project phase updated successfully!', 'success');
    } else {
      if (res.status === 401) {
        showAlert('upload-alert', 'Session expired or invalid. Please click Logout and sign in again.', 'error');
      } else {
        showAlert('upload-alert', data.error || 'Failed to update phase', 'error');
      }
    }
  } catch (err) {
    showAlert('upload-alert', 'Server connection error', 'error');
  }
}

// Initialize phase on load if logged in
document.addEventListener('DOMContentLoaded', () => {
  if (localStorage.getItem('forest_token')) {
    loadCurrentPhase();
  }
});
