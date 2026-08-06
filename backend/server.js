const dns = require('dns');
if (dns.setDefaultResultOrder) {
  dns.setDefaultResultOrder('ipv4first'); // Force IPv4 to fix Telegram EFATAL error
}
const express = require('express');
const mongoose = require('mongoose');
const cors = require('cors');

const app = express();
app.use(cors());
require('./telegram_bot'); // Start the Telegram Bot alongside the Express server
app.use(express.json({ limit: '50mb' }));

mongoose.connect('mongodb+srv://panimalar:panimalar1234@panimalar.binwh1b.mongodb.net/?appName=panimalar')
  .then(() => console.log('✅ Connected to MongoDB Atlas'))
  .catch(err => console.error('❌ MongoDB connection error:', err));

const studentSchema = new mongoose.Schema({
  rollNo: { type: String, required: true, unique: true },
  name: String,
  year: String,
  department: String,
  busNo: String,
  boardingStop: String,
  profilePicBase64: String
});

const Student = mongoose.model('Student', studentSchema);

const voiceMessageSchema = new mongoose.Schema({
  sender: String,
  receiver: String,
  audioBase64: { type: String, required: true },
  timestamp: { type: Date, default: Date.now },
  duration: Number
});

const VoiceMessage = mongoose.model('VoiceMessage', voiceMessageSchema);

const documentSchema = new mongoose.Schema({
  fileName: { type: String, required: true },
  mimeType: { type: String, required: true },
  fileBase64: { type: String, required: true },
  timestamp: { type: Date, default: Date.now }
});

const DocumentModel = mongoose.model('Document', documentSchema);

// GET profile
app.get('/api/students/:rollNo', async (req, res) => {
  try {
    const student = await Student.findOne({ rollNo: req.params.rollNo });
    if (student) {
      res.json(student);
    } else {
      res.status(404).json({ message: 'Student not found' });
    }
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// POST profile
app.post('/api/students/:rollNo', async (req, res) => {
  try {
    const { name, year, department, busNo, boardingStop, profilePicBase64 } = req.body;
    const student = await Student.findOneAndUpdate(
      { rollNo: req.params.rollNo },
      { name, year, department, busNo, boardingStop, profilePicBase64 },
      { new: true, upsert: true }
    );
    res.json(student);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Root endpoint to verify server is running
app.get('/', (req, res) => {
  res.json({ status: '✅ Panimalar Backend is running successfully!' });
});

// POST voice message
app.post('/api/voice', async (req, res) => {
  try {
    const { sender, receiver, audioBase64, duration } = req.body;
    const voiceMessage = new VoiceMessage({ sender, receiver, audioBase64, duration });
    await voiceMessage.save();
    res.json({ id: voiceMessage._id });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// GET voice message
app.get('/api/voice/:id', async (req, res) => {
  try {
    const voiceMessage = await VoiceMessage.findById(req.params.id);
    if (voiceMessage) {
      res.json({ audioBase64: voiceMessage.audioBase64, duration: voiceMessage.duration });
    } else {
      res.status(404).json({ message: 'Voice message not found' });
    }
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// POST document
app.post('/api/documents', async (req, res) => {
  try {
    const { fileName, mimeType, fileBase64 } = req.body;
    if (!fileName || !mimeType || !fileBase64) {
      return res.status(400).json({ error: 'Missing file data' });
    }
    const document = new DocumentModel({ fileName, mimeType, fileBase64 });
    await document.save();
    res.json({ id: document._id });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// GET document (serves binary file for direct URL rendering)
app.get('/api/documents/:id', async (req, res) => {
  try {
    const document = await DocumentModel.findById(req.params.id);
    if (document) {
      const buffer = Buffer.from(document.fileBase64, 'base64');
      res.set('Content-Type', document.mimeType);
      res.send(buffer);
    } else {
      res.status(404).json({ message: 'Document not found' });
    }
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

const PORT = process.env.PORT || 5000;
app.listen(PORT, '0.0.0.0', () => {
  console.log(`🚀 Server running on port ${PORT}`);
});
