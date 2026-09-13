# FOREST Frontend Manual 🎨

This folder contains the visual part of the website that users interact with. It is built using pure HTML, CSS, and JavaScript.

## 📂 File Explanations

### `index.html`
- **What it is:** The Homepage.
- **What it does:** It displays the hero section, the project overview, the roadmap timeline, and the team members. It is completely static.

### `planning-v1.html`
- **What it is:** The Permanent Planning Page.
- **What it does:** It contains the full, detailed FOREST Revised Future Plan & Feasibility Study that you sent to the professor. It is hardcoded to always be available.

### `presentations.html`
- **What it is:** The PPT Presenter / Deliverables Page.
- **What it does:** Uses JavaScript to dynamically list all published PPTs/PDFs. Clicking "View Presentation" opens the file in our custom viewer.

### `viewer.html` (NEW!)
- **What it is:** The Universal Document Viewer.
- **What it does:** When you click "View Presentation" on a file, this page opens. If the file is a PDF, it embeds the browser's native PDF viewer. If the file is a raw PPTX, it uses a powerful JavaScript library (PPTXjs) to render the slides directly in your browser with presentation mode and keyboard shortcuts!

### `admin.html`
- **What it is:** The Admin Dashboard (Hidden Page).
- **What it does:** This is where you login. It contains a login form, a drag-and-drop file upload zone, a form to add a title/version, and a list showing your version history.

### `css/style.css`
- **What it is:** The Premium Stylesheet.
- **What it does:** It handles all the colors, animations, dark mode, glassmorphism effects, and layout for the entire website.

### `js/config.js`
- **What it is:** The Configuration File.
- **What it does:** It contains one line of code: `const API_BASE_URL = 'http://localhost:3000';`. All other frontend files use this variable to know where the backend is located. (You will change this to your server IP when you deploy it).

### `js/admin.js`
- **What it is:** The Logic for the Admin Panel.
- **What it does:** 
  1. **Login:** It sends your email/password to the backend. If correct, it receives a JWT Token and saves it in your browser's `localStorage`.
  2. **Upload:** It takes the files you dragged in, adds your JWT token to the request for security, and sends a "Multipart Form" request to the backend.
  3. **Publish:** It adds a "Publish" button next to unpublished uploads. Clicking it tells the backend to make the presentation visible on the `presentations.html` page.

---

## 🚀 How to Run the Frontend

The frontend is completely static! 
1. Make sure your backend is running first.
2. Simply double-click `index.html` in your file explorer to open it in Chrome/Edge.
3. Because we enabled CORS on the backend, the frontend can talk to it seamlessly.
