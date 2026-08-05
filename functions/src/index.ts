import * as functions from 'firebase-functions/v2';
import * as admin from 'firebase-admin';

admin.initializeApp();

/**
 * Cloud Function que escucha la creacion de documentos en 'alerts'
 * y envia notificaciones push FCM a los destinatarios correspondientes.
 *
 * Requiere plan Blaze (pay-as-you-go) porque Functions necesita
 * llamadas salientes a FCM.
 */
export const sendAlertNotification = functions.firestore.onDocumentCreated(
  {
    document: 'alerts/{alertId}',
    // Cambiar a la region de tu proyecto Firebase si es distinta
    region: 'us-central1',
  },
  async (event) => {
    const alert = event.data?.data();
    if (!alert) return;

    const {
      groupId,
      senderId,
      receiverId,
      type,
      payload,
      senderName,
    } = alert;

    if (!groupId || !senderId) return;

    // -------------------------------------------------------------------------
    // 1. Obtener tokens destinatarios
    // -------------------------------------------------------------------------
    const tokens: string[] = [];

    if (receiverId !== 'all') {
      // Mensaje privado: solo al destinatario
      const doc = await admin.firestore().doc(`users/${receiverId}`).get();
      const token = doc.data()?.fcmToken;
      if (token && typeof token === 'string') tokens.push(token);
    } else {
      // Mensaje grupal: a todos los miembros excepto el remitente
      const members = await admin
        .firestore()
        .collection('users')
        .where('groupId', '==', groupId)
        .get();

      members.docs.forEach((doc) => {
        if (doc.id !== senderId) {
          const token = doc.data().fcmToken;
          if (token && typeof token === 'string') tokens.push(token);
        }
      });
    }

    if (tokens.length === 0) return;

    // -------------------------------------------------------------------------
    // 2. Armar contenido de la notificacion
    // -------------------------------------------------------------------------
    let title: string;
    let body: string;

    switch (type) {
      case 'SOS':
        title = 'S.O.S - MiClan';
        body = `ALERTA DE PANICO de ${senderName || 'Alguien'}`;
        break;
      case 'photo':
        title = `MiClan - ${senderName || 'Alguien'}`;
        body = 'Te envio una foto';
        break;
      case 'audio':
        title = `MiClan - ${senderName || 'Alguien'}`;
        body = 'Te envio un audio';
        break;
      case 'system':
        title = 'MiClan';
        body = payload || 'Novedad del grupo';
        break;
      default:
        title = `MiClan - ${senderName || 'Alguien'}`;
        body = payload || 'Nuevo mensaje';
    }

    // -------------------------------------------------------------------------
    // 3. Enviar FCM v1 (multicast)
    // -------------------------------------------------------------------------
    const message = {
      tokens,
      notification: { title, body },
      data: {
        type: type || 'message',
        groupId: groupId || '',
        senderId: senderId || '',
        alertId: event.params.alertId,
        click_action: 'FLUTTER_NOTIFICATION_CLICK',
      },
      android: {
        notification: {
          channelId: type === 'SOS' ? 'sos_channel' : 'msg_channel',
          priority: type === 'SOS' ? 'high' : 'default',
          sound: type === 'SOS' ? 'default' : 'default',
        },
      },
    };

    const response = await admin.messaging().sendEachForMulticast(message);

    // -------------------------------------------------------------------------
    // 4. Limpiar tokens invalidos
    // -------------------------------------------------------------------------
    response.responses.forEach((resp, idx) => {
      if (!resp.success) {
        const code = resp.error?.code;
        if (
          code === 'messaging/invalid-registration-token' ||
          code === 'messaging/registration-token-not-registered'
        ) {
          const badToken = tokens[idx];
          admin
            .firestore()
            .collection('users')
            .where('fcmToken', '==', badToken)
            .get()
            .then((snap) => {
              snap.docs.forEach((d) =>
                d.ref.update({ fcmToken: admin.firestore.FieldValue.delete() })
              );
            })
            .catch(() => {});
        }
      }
    });
  }
);
