const functions = require("firebase-functions");
const admin = require("firebase-admin");
admin.initializeApp();

exports.onAlertCreated = functions.firestore
  .document("alerts/{alertId}")
  .onCreate(async (snap, context) => {
    const alertData = snap.data();
    const groupId = alertData.groupId;
    const senderId = alertData.senderId;
    const receiverId = alertData.receiverId;
    const type = alertData.type;

    try {
      const membersSnapshot = await admin.firestore()
        .collection("users")
        .where("groupId", "==", groupId)
        .get();

      const tokens = [];
      for (const doc of membersSnapshot.docs) {
        const userData = doc.data();
        if (doc.id !== senderId && userData.fcmToken) {
          if (receiverId === 'all' || receiverId === doc.id) {
            tokens.push(userData.fcmToken);
          }
        }
      }

      if (tokens.length === 0) return null;

      let title, body;
      switch (type) {
        case 'SOS':
          title = "?? ALERTA S.O.S";
          body = "?Un miembro ha activado el bot車n de p芍nico!";
          break;
        case 'quick_message':
          title = "?? Mensaje R芍pido";
          body = alertData.payload || "Nuevo mensaje";
          break;
        case 'command_message':
          title = "?? Mensaje de la Central";
          body = alertData.payload || "La Central te env赤a un mensaje";
          break;
        case 'photo':
          title = "?? Foto recibida";
          body = "Un miembro envi車 una foto";
          break;
        case 'audio':
          title = "?? Audio recibido";
          body = "Un miembro envi車 una nota de audio";
          break;
        case 'geofence':
          title = "?? Alerta de Zona";
          body = alertData.payload || "Un miembro cruz車 el l赤mite de zona";
          break;
        default:
          title = "Notificaci車n MiClan";
          body = "Nueva notificaci車n";
      }

      const message = {
        tokens: tokens,
        notification: { title, body },
        data: { type, alertId: context.params.alertId },
        android: {
          priority: "high",
          notification: {
            sound: "default",
            channel_id: "miclan_critical_channel",
          },
        },
      };

      const response = await admin.messaging().sendEachForMulticast(message);
      console.log(`FCM enviado a ${response.successCount} dispositivos`);
      await snap.ref.update({
        notified: true,
        notifiedAt: admin.firestore.FieldValue.serverTimestamp()
      });
      return null;
    } catch (error) {
      console.error("Error FCM:", error);
      return null;
    }
  });