const functions = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();

exports.sendNotification = functions.firestore
  .document('alerts/{alertId}')
  .onCreate(async (snap, context) => {
    const alert = snap.data();
    const groupId = alert.groupId;
    const senderId = alert.senderId;
    const receiverId = alert.receiverId;
    const type = alert.type;
    const payload = alert.payload;
    const senderName = alert.senderName;

    if (!groupId) {
      return null;
    }

    let tokens = [];
    if (receiverId !== 'all') {
      const userDoc = await admin.firestore().collection('users').doc(receiverId).get();
      const token = userDoc.data()?.fcmToken;
      if (token) {
        tokens.push(token);
      }
    } else {
      const members = await admin.firestore()
        .collection('users')
        .where('groupId', '==', groupId)
        .get();
      members.docs.forEach((doc) => {
        if (doc.id !== senderId) {
          const token = doc.data().fcmToken;
          if (token) {
            tokens.push(token);
          }
        }
      });
    }

    if (tokens.length === 0) {
      return null;
    }

    let title;
    let body;
    if (type === 'SOS') {
      title = 'S.O.S - MiClan';
      body = 'ALERTA DE PANICO de ' + (senderName || 'Miembro');
    } else if (type === 'photo') {
      title = (senderName || 'Miembro');
      body = 'Te envio una foto';
    } else if (type === 'audio') {
      title = (senderName || 'Miembro');
      body = 'Te envio un audio';
    } else {
      title = (senderName || 'Miembro');
      body = payload;
    }

    const message = {
      tokens: tokens,
      notification: {
        title: title,
        body: body
      },
      data: {
        type: type,
        groupId: groupId,
        alertId: context.params.alertId
      },
      android: {
        priority: type === 'SOS' ? 'high' : 'normal',
        notification: {
          channelId: type === 'SOS' ? 'sos_channel' : 'msg_channel',
          sound: 'default'
        }
      }
    };

    try {
      const response = await admin.messaging().sendEachForMulticast(message);
      console.log('Notificaciones enviadas: ' + response.successCount);
    } catch (error) {
      console.error('Error enviando: ' + error);
    }

    return null;
  });
