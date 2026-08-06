const functions = require('firebase-functions');
const admin = require('firebase-admin');
const axios = require('axios');

admin.initializeApp();

// ============================================================================
// sendAlertNotification - Cloud Function v1 (FCM HTTP v1)
// ============================================================================
// CAMBIOS CLAVE para Doze / sueño profundo:
// 1. TODOS los mensajes usan android.priority = 'high'
// 2. Se agrega TTL de 3600s
// 3. Se limpian tokens invalidos automaticamente
// ============================================================================

exports.sendAlertNotification = functions.firestore.document('alerts/{alertId}').onCreate(async (snap, context) => {
  const alert = snap.data();
  const alertId = context.params.alertId;

  if (!alert || !alert.groupId) {
    console.log('Alerta sin groupId, skip');
    return null;
  }

  const { groupId, senderId, receiverId, type, payload, senderName } = alert;

  // Obtener tokens FCM de todos los miembros del grupo
  const usersSnap = await admin.firestore()
    .collection('users')
    .where('groupId', '==', groupId)
    .get();

  const tokens = [];
  const tokenToUid = {};

  usersSnap.forEach(doc => {
    const uid = doc.id;
    if (uid === senderId) return;
    if (receiverId !== 'all' && uid !== receiverId) return;

    const token = doc.data().fcmToken;
    if (token && typeof token === 'string' && token.length > 20) {
      tokens.push(token);
      tokenToUid[token] = uid;
    }
  });

  if (tokens.length === 0) {
    console.log('No hay tokens validos para este grupo');
    return null;
  }

  // Obtener access token OAuth2
  let accessToken;
  try {
    const tokenResponse = await admin.credential.applicationDefault().getAccessToken();
    accessToken = tokenResponse.access_token;
  } catch (err) {
    console.error('Error obteniendo access token:', err);
    return null;
  }

  const projectId = admin.instanceId().app.options.projectId;
  const fcmUrl = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;

  // Construir titulo y cuerpo segun tipo
  let title, body, channelId;
  const displayName = senderName || 'MiClan';

  switch (type) {
    case 'SOS':
      title = 'S.O.S - MiClan';
      body = 'ALERTA DE PANICO ACTIVADA!';
      channelId = 'sos_channel';
      break;
    case 'photo':
      title = `MiClan - ${displayName}`;
      body = 'Te envio una foto';
      channelId = 'msg_channel';
      break;
    case 'audio':
      title = `MiClan - ${displayName}`;
      body = 'Te envio un audio';
      channelId = 'msg_channel';
      break;
    case 'command_message':
      title = `Comando - ${displayName}`;
      body = payload;
      channelId = 'msg_channel';
      break;
    case 'geofence':
      title = 'MiClan - Geofence';
      body = payload;
      channelId = 'geofence_channel';
      break;
    case 'system':
      title = 'MiClan';
      body = payload;
      channelId = 'msg_channel';
      break;
    default:
      title = `MiClan - ${displayName}`;
      body = payload;
      channelId = 'msg_channel';
  }

  // Enviar a cada token individualmente
  const sendPromises = tokens.map(async (token) => {
    const message = {
      message: {
        token: token,
        data: {
          type: type || 'msg',
          alertId: alertId,
          groupId: groupId,
          senderId: senderId || '',
          receiverId: receiverId || 'all',
        },
        notification: {
          title: title,
          body: body,
        },
        android: {
          priority: 'high',
          ttl: '3600s',
          directBootOk: true,
          notification: {
            channelId: channelId,
            sound: 'default',
            priority: 'high',
            visibility: 'public',
            fullScreenIntent: type === 'SOS',
          },
        },
      },
    };

    try {
      await axios.post(fcmUrl, message, {
        headers: {
          Authorization: `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
        },
        timeout: 15000,
      });
      console.log(`FCM enviado OK a ${tokenToUid[token]}`);
    } catch (err) {
      const errMsg = err.response?.data?.error?.message || err.message;
      console.error(`FCM fallo para ${tokenToUid[token]}: ${errMsg}`);

      if (errMsg.includes('UNREGISTERED') || errMsg.includes('INVALID_ARGUMENT')) {
        const uid = tokenToUid[token];
        if (uid) {
          await admin.firestore().collection('users').doc(uid).update({ fcmToken: admin.firestore.FieldValue.delete() });
          console.log(`Token invalido eliminado para ${uid}`);
        }
      }
    }
  });

  await Promise.all(sendPromises);
  console.log(`Procesados ${tokens.length} tokens para alerta ${alertId}`);
  return null;
});