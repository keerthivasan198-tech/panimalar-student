require('dotenv').config();
const TelegramBot = require('node-telegram-bot-api').default || require('node-telegram-bot-api');
const { initializeApp } = require('firebase/app');
const { getDatabase, ref, onValue, onChildAdded, get } = require('firebase/database');
const fs = require('fs');
const path = require('path');

// Telegram token
const token = process.env.TELEGRAM_TOKEN || '8887004131:AAEM7TMtPSBrFNyiE2Ws4bHPd99O0vB4U9E';
const bot = new TelegramBot(token, { polling: true });

// Firebase configuration from Flutter app
const firebaseConfig = {
  apiKey: "AIzaSyBUozEQcU48yRBSSM3EquhV8Sm1vWtRPFY",
  appId: "1:538185362536:web:e8d35e63d4c641979c1fdd",
  messagingSenderId: "538185362536",
  projectId: "gen-lang-client-0636615491",
  databaseURL: "https://gen-lang-client-0636615491-default-rtdb.asia-southeast1.firebasedatabase.app"
};

const app = initializeApp(firebaseConfig);
const db = getDatabase(app);

const SUBSCRIBERS_FILE = path.join(__dirname, 'subscribers.json');

function getSubscribers() {
  if (!fs.existsSync(SUBSCRIBERS_FILE)) {
    return {};
  }
  const data = JSON.parse(fs.readFileSync(SUBSCRIBERS_FILE, 'utf8'));
  if (Array.isArray(data)) {
    const newData = {};
    data.forEach(id => newData[id] = "all");
    return newData;
  }
  return data;
}

function saveSubscriber(chatId, busId = "all") {
  const subs = getSubscribers();
  subs[chatId] = busId;
  fs.writeFileSync(SUBSCRIBERS_FILE, JSON.stringify(subs, null, 2));
  return true;
}

function sendToBus(targetBus, message) {
  const subs = getSubscribers();
  Object.keys(subs).forEach(chatId => {
    const assignedBus = subs[chatId];
    if (assignedBus === 'all' || assignedBus === targetBus || targetBus === 'all') {
      bot.sendMessage(chatId, message, { parse_mode: 'Markdown' }).catch(err => {
        console.error(`Error sending message to ${chatId}:`, err.message);
      });
    }
  });
}

// Telegram commands
bot.onText(/\/setbus (.+)/, (msg, match) => {
  const chatId = msg.chat.id;
  const busId = match[1].toLowerCase().trim();
  saveSubscriber(chatId, busId);
  bot.sendMessage(chatId, `✅ This group is now registered to receive notifications specifically for *Bus ${busId}*.`, { parse_mode: 'Markdown' });
});

bot.onText(/\/start/, (msg) => {
  const chatId = msg.chat.id;
  bot.sendMessage(chatId, '🚌 Welcome to Panimalar Transit Bot!\n\nTo link this group to a specific bus, type `/setbus <busNumber>` (for example: `/setbus 52`).', { parse_mode: 'Markdown' });
});

// Watch for Bus Live Locations (Started)
const previousBusStatuses = {};
onValue(ref(db, 'liveLocations'), (snapshot) => {
  const data = snapshot.val();
  if (!data) return;
  
  Object.keys(data).forEach(busId => {
    const currentStatus = data[busId].status || 'offline';
    const prevStatus = previousBusStatuses[busId];
    
    if (prevStatus !== undefined && prevStatus !== 'tracking' && currentStatus === 'tracking') {
      sendToBus(busId.toLowerCase().trim(), `✅ *Bus ${busId} has started its journey!* You can now track it live.`);
    }
    previousBusStatuses[busId] = currentStatus;
  });
});

// Watch for Breakdowns for All Buses
const previousBreakdownTimes = {};
onValue(ref(db, 'breakdowns'), (snapshot) => {
  const data = snapshot.val();
  if (!data) return;

  Object.keys(data).forEach(busId => {
    const breakdownData = data[busId];
    const isBreakdownActive = breakdownData.active === true;
    const timestamp = breakdownData.timestamp;
    const prevTime = previousBreakdownTimes[busId];
    
    if (isBreakdownActive && timestamp !== prevTime) {
      previousBreakdownTimes[busId] = timestamp;
      const replacementBus = breakdownData.replacementBus || 'Pending';
      if (replacementBus === 'Pending') {
        sendToBus(busId.toLowerCase().trim(), `⚠️ *Bus ${busId} Breakdown Alert!*\n\nA breakdown has been reported. Replacement bus dispatch is pending. Please stay at your stop.`);
      } else {
        sendToBus(busId.toLowerCase().trim(), `⚠️ *Bus ${busId} Breakdown Update!*\n\nReplacement Bus *${replacementBus}* has been dispatched. Please stay at your stop.`);
      }
    }
  });
});

// Watch for General Notifications meant for Bus 52 or All
let initialLoad = true;
const handledNotifs = new Set();
onChildAdded(ref(db, 'student_notifications'), (snapshot) => {
  if (initialLoad) return; // Skip historical notifications
  const data = snapshot.val();
  if (!data) return;
  
  const notifId = snapshot.key;
  if (handledNotifs.has(notifId)) return;
  handledNotifs.add(notifId);
  
  const target = (data.bus || 'all').toString().toLowerCase().trim();
  const title = data.title || 'Notification';
  const body = data.msg || '';
  
  // Broadcast notifications specifically to the targeted bus (or to all if it targets 'all')
  const busPrefix = target === 'all' ? '' : `[Bus ${data.bus}] `;
  sendToBus(target, `📢 *${busPrefix}${title}*\n\n${body}`);
});

// Give the Firebase client a couple of seconds to do initial loads before processing new child_added events
setTimeout(() => {
  initialLoad = false;
  console.log('Started listening to new Firebase events...');
}, 5000);

console.log('Telegram Bot is running...');
