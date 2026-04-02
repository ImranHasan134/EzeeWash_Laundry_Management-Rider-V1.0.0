import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

serve(async (req) => {
  try {
    const payload = await req.json();
    const newRecord = payload.record;
    const oldRecord = payload.old_record || {};

    console.log(`🔔 Webhook triggered for Order ID: ${newRecord.id}`);

    // 1. SMART CHECK: Ignore if status hasn't changed
    if (oldRecord.status && oldRecord.status === newRecord.status) {
      console.log("⏭️ Status unchanged. Skipping.");
      return new Response("Status unchanged", { status: 200 });
    }

    // 2. Get Rider ID
    const riderId = newRecord.rider_id || newRecord.pickup_rider_id || newRecord.delivery_rider_id;

    if (!riderId) {
      console.log("❌ No rider assigned. Exiting.");
      return new Response("No rider", { status: 200 });
    }

    // 🚨 PASTE YOUR EXACT KEYS HERE 🚨
    const ONESIGNAL_APP_ID = "98573413-e76f-4636-9442-40cce7f1e70e";
    const ONESIGNAL_REST_API_KEY = "os_v2_app_tbltie7hn5ddnfccidgop4phbykr7fbpwofuxm4wmj5hglkl6bwuj7efh5lxquokyqb37jxnnbh3zb7l32iezulpufsd7y2yfki6uoi";

    // 3. STATUS CHECKER
    const status = newRecord.status;
    let titleText = "";
    let bodyText = "";

    if (status === 'picked_up') {
      titleText = "New Pickup Task! 🏍️";
      bodyText = `Order #${newRecord.order_number || 'Update'} is ready for pickup.`;
    }
    else if (status === 'in_process') {
      titleText = "Drop-off Confirmed ✅";
      bodyText = `Order Picked Up and Dropped Successfully.`;
    }
    else if (status === 'out_for_delivery') {
      titleText = "New Delivery Task! 📦";
      bodyText = `Order #${newRecord.order_number || 'Update'} is ready for delivery.`;
    }
    else if (status === 'delivered') {
      titleText = "Delivery Confirmed 🎉";
      bodyText = `Order Delivered Successfully.`;
    }
    else {
      console.log(`Status is ${status}, no push needed.`);
      return new Response("No notification needed", { status: 200 });
    }

    console.log(`📤 Sending '${titleText}' to Rider: ${riderId}`);

    // 4. Send to OneSignal
    const response = await fetch("https://onesignal.com/api/v1/notifications", {
      method: "POST",
      headers: {
        "Content-Type": "application/json; charset=utf-8",
        "Authorization": `Basic ${ONESIGNAL_REST_API_KEY}` // MUST HAVE THE WORD Basic
      },
      body: JSON.stringify({
        app_id: ONESIGNAL_APP_ID,
        target_channel: "push",
        include_aliases: {
          external_id: [String(riderId)]
        },
        headings: { "en": titleText },
        contents: { "en": bodyText }
      })
    });

    const result = await response.json();
    console.log("OneSignal Response:", result);

    if (result.errors) {
      throw new Error(JSON.stringify(result.errors));
    }

    return new Response(JSON.stringify({ success: true, result }), { status: 200 });

  } catch (error) {
    console.error("🔥 FATAL ERROR:", error.message);
    return new Response(JSON.stringify({ error: error.message }), { status: 500 });
  }
});