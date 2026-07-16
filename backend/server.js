const express = require('express');
const mongoose = require('mongoose');
const cors = require('cors');

const app = express();
app.use(cors());
app.use(express.json({ limit: '10mb' }));

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

const PORT = 5000;
app.listen(PORT, () => {
  console.log(`🚀 Server running on port ${PORT}`);
});
