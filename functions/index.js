const functions = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();

/**
 * Cloud Function que escucha la coleccion 'alerts' y envia
 * notificaciones push FCM a todos los miembros del grupo.
 */
exports.sendAlertNotification = functions.firestore
  .document('alerts/{alertId}')
  .onCreate(async (snap, context) => {
    const alert = snap.data();
    if (!alert) return null;

    const { groupId, senderId, receiverId, type, payload, senderName } = alert;

    // Obtener todos los miembros del grupo
    const usersSnap = await admin.firestore()
      .collection('users')
      .where('groupId', '==', groupId)
      .get();

    const tokens = [];
    const tokenToUid = {};

    usersSnap.forEach(doc => {
      const data = doc.data();
      // No enviar al que envio el mensaje
      if (doc.id !== senderId && data.fcmToken) {
        // Si es privado, solo al destinatario
        if (receiverId !== 'all' && doc.id !== receiverId) return;
        tokens.push(data.fcmToken);
        tokenToUid[data.fcmToken] = doc.id;
      }
    });

    if (tokens.length === 0) {
      console.log('No hay tokens FCM validos para este grupo');
      return null;
    }

    const isSOS = type === 'SOS';
    const isCommand = type === 'command_message';

    const title = isSOS 
      ? 'S.O.S - MiClan' 
      : isCommand 
        ? 'Comando - ' + (senderName || 'Grupo')
        : 'MiClan - ' + (senderName || 'Grupo');

    const body = isSOS 
      ? 'ALERTA DE PANICO ACTIVADA!' 
      : payload;

    const message = {
      tokens: tokens,
      data: {
        type: type || 'message',
        alertId: context.params.alertId,
        groupId: groupId,
        senderId: senderId,
        receiverId: receiverId,
      },
      notification: {
        title: title,
        body: body,
      },
      android: {
        priority: 'high',
        notification: {
          channelId: isSOS ? 'sos_channel' : 'msg_channel',
          sound: 'default',
          priority: 'high',
          visibility: 'public',
        },
      },
      apns: {
        payload: {
          aps: {
            sound: 'default',
            badge: 1,
            alert: {
              title: title,
              body: body,
            },
          },
        },
      },
    };

    // Para SOS: agregar fullScreenIntent
    if (isSOS) {
      message.android.notification.fullScreenIntent = true;
    }

    try {
      const response = await admin.messaging().sendEachForMulticast(message);
      console.log('Notificaciones enviadas: ' + response.successCount + '/' + tokens.length);

      // Limpiar tokens invalidos
      response.responses.forEach((resp, idx) => {
        if (!resp.success) {
          const errorCode = resp.error?.code;
          if (errorCode === 'messaging/registration-token-not-registered' ||
              errorCode === 'messaging/invalid-registration-token') {
            const badToken = tokens[idx];
            const uid = tokenToUid[badToken];
            if (uid) {
              console.log('Eliminando token invalido para usuario ' + uid);
              admin.firestore().collection('users').doc(uid).update({
                fcmToken: admin.firestore.FieldValue.delete()
              }).catch(() => {});
            }
          }
        }
      });
    } catch (error) {
      console.error('Error enviando notificaciones:', error);
    }

    return null;
  });
