/*
 * Nextcloud Talk application
 *
 * @author Mario Danic
 * Copyright (C) 2017 Mario Danic <mario@lovelyhq.com>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

package com.nextcloud.talk.services.firebase;

import android.annotation.SuppressLint;
import android.app.Notification;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.media.RingtoneManager;
import android.os.Bundle;
import android.util.Base64;
import android.util.Log;

import com.bluelinelabs.logansquare.LoganSquare;
import com.google.firebase.messaging.FirebaseMessagingService;
import com.google.firebase.messaging.RemoteMessage;
import com.nextcloud.talk.R;
import com.nextcloud.talk.activities.CallActivity;
import com.nextcloud.talk.api.models.json.push.DecryptedPushMessage;
import com.nextcloud.talk.api.models.json.push.PushMessage;
import com.nextcloud.talk.models.SignatureVerification;
import com.nextcloud.talk.utils.PushUtils;
import com.nextcloud.talk.utils.bundle.BundleBuilder;

import java.security.InvalidKeyException;
import java.security.NoSuchAlgorithmException;
import java.security.PrivateKey;
import java.util.Calendar;
import java.util.zip.CRC32;

import javax.crypto.Cipher;
import javax.crypto.NoSuchPaddingException;

public class MagicFirebaseMessagingService extends FirebaseMessagingService {
    private static final String TAG = "MagicFirebaseMessagingService";

    @SuppressLint("LongLogTag")
    @Override
    public void onMessageReceived(RemoteMessage remoteMessage) {
        if (remoteMessage.getData() != null) {
            try {
                PushMessage pushMessage = new PushMessage();
                pushMessage.setSubject(remoteMessage.getData().get("subject"));
                pushMessage.setSignature(remoteMessage.getData().get("signature"));

                byte[] base64DecodedSubject = android.util.Base64.decode(pushMessage.getSubject(), Base64.DEFAULT);
                byte[] base64DecodedSignature = android.util.Base64.decode(pushMessage.getSignature(), Base64.DEFAULT);
                PushUtils pushUtils = new PushUtils();
                PrivateKey privateKey = (PrivateKey) pushUtils.readKeyFromFile(false);

                try {
                    SignatureVerification signatureVerification = pushUtils.verifySignature(base64DecodedSignature,
                            base64DecodedSubject);

                    if (signatureVerification.isSignatureValid()) {
                        Cipher cipher = Cipher.getInstance("RSA/None/PKCS1Padding");
                        cipher.init(Cipher.DECRYPT_MODE, privateKey);
                        byte[] decryptedSubject = cipher.doFinal(base64DecodedSubject);
                        DecryptedPushMessage decryptedPushMessage = LoganSquare.parse(new String(decryptedSubject),
                                DecryptedPushMessage.class);

                        if (decryptedPushMessage.getApp().equals("spreed")) {
                            int smallIcon;
                            Bitmap largeIcon;
                            String category = "";
                            int priority = Notification.PRIORITY_DEFAULT;

                            Intent intent = new Intent(this, CallActivity.class);
                            BundleBuilder bundleBuilder = new BundleBuilder(new Bundle());
                            bundleBuilder.putString("roomToken", decryptedPushMessage.getId());
                            bundleBuilder.putParcelable("userEntity", signatureVerification.getUserEntity());
                            intent.putExtras(bundleBuilder.build());

                            PendingIntent pendingIntent = PendingIntent.getActivity(this,
                                    0, intent, PendingIntent.FLAG_CANCEL_CURRENT);

                            switch (decryptedPushMessage.getType()) {
                                case "call":
                                    smallIcon = R.drawable.ic_call_black_24dp;
                                    category = Notification.CATEGORY_CALL;
                                    priority = Notification.PRIORITY_HIGH;
                                    break;
                                case "room":
                                    smallIcon = R.drawable.ic_notifications_black_24dp;
                                    category = Notification.CATEGORY_CALL;
                                    priority = Notification.PRIORITY_HIGH;
                                    break;
                                case "chat":
                                    smallIcon = R.drawable.ic_chat_black_24dp;
                                    category = Notification.CATEGORY_MESSAGE;
                                    break;
                                default:
                                    smallIcon = R.drawable.ic_logo;
                            }

                            largeIcon = BitmapFactory.decodeResource(getResources(), smallIcon);

                            Notification.Builder notificationBuilder = new Notification.Builder(this)
                                    .setSmallIcon(smallIcon)
                                    .setLargeIcon(largeIcon)
                                    .setColor(getColor(R.color.colorPrimary))
                                    .setCategory(category)
                                    .setPriority(priority)
                                    .setWhen(Calendar.getInstance().getTimeInMillis())
                                    .setShowWhen(true)
                                    .setSubText(signatureVerification.getUserEntity().getDisplayName())
                                    .setContentTitle(decryptedPushMessage.getSubject())
                                    .setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION))
                                    .setAutoCancel(true);

                            if (!"call".equals(decryptedPushMessage.getType())) {
                                notificationBuilder.setContentIntent(pendingIntent);
                            } else {
                                notificationBuilder.setFullScreenIntent(pendingIntent, true);
                            }

                            NotificationManager notificationManager =
                                    (NotificationManager) getSystemService(Context.NOTIFICATION_SERVICE);

                            if (notificationManager != null) {
                                String stringForCrc = decryptedPushMessage.getSubject() + " " + signatureVerification
                                        .getUserEntity().getDisplayName() + " " + signatureVerification.getUserEntity
                                        ().getBaseUrl();

                                CRC32 crc32 = new CRC32();
                                crc32.update(stringForCrc.getBytes());

                                notificationManager.notify((int) crc32.getValue(), notificationBuilder.build());
                            }
                        }
                    }
                } catch (NoSuchAlgorithmException e1) {
                    Log.d(TAG, "No proper algorithm to decrypt the message " + e1.getLocalizedMessage());
                } catch (NoSuchPaddingException e1) {
                    Log.d(TAG, "No proper padding to decrypt the message " + e1.getLocalizedMessage());
                } catch (InvalidKeyException e1) {
                    Log.d(TAG, "Invalid private key " + e1.getLocalizedMessage());
                }
            } catch (Exception exception) {
                Log.d(TAG, "Something went very wrong" + exception.getLocalizedMessage());
            }
        } else {
            Log.d(TAG, "The data we received was empty");

        }
    }
}
