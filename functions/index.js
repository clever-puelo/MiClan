const functions = require('firebase-functions');
const admin = require('firebase-admin');
const axios = require('axios');

admin.initializeApp();

exports.sendAlertNotification = functions.firestore
  .document('alerts/{alertId}')
  .onCreate(async (snap, context) => {
    const alert = snap.data();
    if (!alert) return null;

    const { groupId, senderId, receiverId, type, payload, senderName } = alert;

    try {
      const usersSnapshot = await admin.firestore()
        .collection('users')
        .where('groupId', '==', groupId)
        .get();

      const tokens = [];
      const invalidTokens = [];

      usersSnapshot.forEach(doc => {
        if (doc.id === senderId) return;
        if (receiverId !== 'all' && doc.id !== receiverId) return;
        const fcmToken = doc.data().fcmToken;
        if (fcmToken && fcmToken.length > 0) {
          tokens.push({ uid: doc.id, token: fcmToken });
        }
      });

      if (tokens.length === 0) return null;

      let title, body, channelId, fullScreenIntent;
      switch (type) {
        case 'SOS':
          title = 'S.O.S - MiClan';
          body = `ALERTA DE PANICO ACTIVADA por ${senderName || 'Desconocido'}`;
          channelId = 'sos_channel';
          fullScreenIntent = true;
          break;
        case 'command_message':
          title = 'MiClan - Comando';
          body = `${senderName || 'Desconocido'}: ${payload}`;
          channelId = 'msg_channel';
          break;
        case 'photo':
          title = `MiClan - ${senderName || 'Desconocido'}`;
          body = 'Te envio una foto';
          channelId = 'msg_channel';
          break;
        case 'audio':
          title = `MiClan - ${senderName || 'Desconocido'}`;
          body = 'Te envio un audio';
          channelId = 'msg_channel';
          break;
        default:
          title = `MiClan - ${senderName || 'Desconocido'}`;
          body = payload || 'Nuevo mensaje';
          channelId = 'msg_channel';
      }

      const accessToken = await admin.credential.applicationDefault().getAccessToken();
      const projectId = admin.instanceId().app.options.projectId;
      const fcmUrl = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;

      const results = await Promise.all(tokens.map(async ({ uid, token }) => {
        const message = {
          message: {
            token: token,
            data: { type: type || '', alertId: context.params.alertId, groupId, senderId, receiverId },
            notification: { title, body },
            android: {
              priority: type === 'SOS' ? 'high' : 'normal',
              notification: { channelId, sound: 'default', fullScreenIntent },
            },
          },
        };
        try {
          await axios.post(fcmUrl, message, {
            headers: { 'Authorization': `Bearer ${accessToken.access_token}`, 'Content-Type': 'application/json' },
            timeout: 10000,
          });
          return { success: true, uid };
        } catch (error) {
          const code = error.response?.data?.error?.details?.[0]?.errorCode || error.code;
          if (code === 'UNREGISTERED' || code === 'INVALID_ARGUMENT' || code === 'registration-token-not-registered') {
            invalidTokens.push(uid);
          }
          return { success: false, uid, error: code };
        }
      }));

      if (invalidTokens.length > 0) {
        const batch = admin.firestore().batch();
        for (const uid of invalidTokens) {
          batch.update(admin.firestore().collection('users').doc(uid), { fcmToken: admin.firestore.FieldValue.delete() });
        }
        await batch.commit();
      }

      console.log(`Notifications: ${results.filter(r => r.success).length}/${tokens.length}`);
      return { success: true };

    } catch (error) {
      console.error('Error:', error);
      return { success: false, error: error.message };
    }
  });