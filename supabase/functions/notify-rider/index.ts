import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

serve(async (req) => {
  try {
    const payload = await req.json();
    const newRecord = payload.record;
    const oldRecord = payload.old_record || {};

    console.log(`🔔 Webhook triggered for Order ID: ${newRecord.id}`);

    // Ignore if status hasn't changed
    if (oldRecord.status && oldRecord.status === newRecord.status) {
      return new Response("Status unchanged", { status: 200 });
    }

    const ONESIGNAL_APP_ID = Deno.env.get("Rider_ONESIGNAL_APP_ID");
    const ONESIGNAL_REST_API_KEY = Deno.env.get("Rider_ONESIGNAL_REST_API_KEY");

    const status = newRecord.status;
    let titleText = "";
    let bodyText = "";
    let targetRiderId = null;

    // --- THE EXACT HANDSHAKE TIMING ---
    if (status === 'assign_pickup') {
      // Fires when Admin clicks "Assign Rider & PickUp"
      titleText = "New Pickup Task! 🏍️";
      bodyText = `Order #${newRecord.order_number || 'Update'} is ready for pickup.`;
      targetRiderId = newRecord.pickup_rider_id;
    }
    else if (status === 'received') {
      // Fires when Admin clicks "RECEIVED"
      titleText = "Drop-off Confirmed ✅";
      bodyText = `Dropped Order #${newRecord.order_number || 'Update'} successfully.`;
      targetRiderId = newRecord.pickup_rider_id;
    }
    else if (status === 'out_for_delivery') {
      // Fires when Admin clicks "Dispatch Delivery"
      titleText = "New Delivery Task! 📦";
      bodyText = `Order #${newRecord.order_number || 'Update'} is ready for delivery.`;
      targetRiderId = newRecord.delivery_rider_id;
    }
    else if (status === 'delivered') {
      // Fires when Rider clicks "Payment Collected"
      titleText = "Delivery Confirmed 🎉";
      bodyText = `Order Delivered Successfully.`;
      targetRiderId = newRecord.delivery_rider_id;
    }
    else {
      console.log(`Status is ${status}, no push needed.`);
      return new Response("No notification needed", { status: 200 });
    }

    if (!targetRiderId) {
      console.log(`❌ No target rider assigned for status ${status}. Exiting.`);
      return new Response("No target rider", { status: 200 });
    }

    console.log(`📤 Sending '${titleText}' to Rider: ${targetRiderId}`);

    const response = await fetch("https://onesignal.com/api/v1/notifications", {
      method: "POST",
      headers: {
        "Content-Type": "application/json; charset=utf-8",
        "Authorization": `Basic ${ONESIGNAL_REST_API_KEY}`
      },
      body: JSON.stringify({
        app_id: ONESIGNAL_APP_ID,
        target_channel: "push",
        include_aliases: {
          external_id: [String(targetRiderId)]
        },
        headings: { "en": titleText },
        contents: { "en": bodyText }
      })
    });

    const result = await response.json();
    return new Response(JSON.stringify({ success: true, result }), { status: 200 });

  } catch (error) {
    console.error("🔥 FATAL ERROR:", error.message);
    return new Response(JSON.stringify({ error: error.message }), { status: 500 });
  }
});