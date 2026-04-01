import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

serve(async (req) => {
  try {
    const payload = await req.json();
    const newRecord = payload.record;
    const oldRecord = payload.old_record || {}; // Grab the old record to compare changes

    console.log(`Webhook triggered for Order ID: ${newRecord.id}`);

    // 1. SMART CHECK: Did the status actually change?
    // If the status is exactly the same as before, ignore this update to prevent duplicate spam.
    if (oldRecord.status && oldRecord.status === newRecord.status) {
      console.log("Status did not change. Ignoring update.");
      return new Response("Status unchanged, ignoring.", { status: 200 });
    }

    // 2. Get Rider ID
    const riderId = newRecord.rider_id || newRecord.pickup_rider_id || newRecord.delivery_rider_id;

    if (!riderId) {
      console.log("No rider assigned yet. Exiting.");
      return new Response("No rider assigned, ignoring.", { status: 200 });
    }

    const ONESIGNAL_APP_ID = Deno.env.get("Rider_ONESIGNAL_APP_ID") ?? "";
    const ONESIGNAL_REST_API_KEY = Deno.env.get("Rider_ONESIGNAL_REST_API_KEY") ?? "";

    // 3. SMART STATUS CHECKER
    const status = newRecord.status;
    let titleText = "";
    let bodyText = "";
    let shouldNotify = true;

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
      // If it's any other status (like 'pending' or 'confirmed'), don't spam the rider
      shouldNotify = false;
    }

    if (!shouldNotify) {
      console.log(`Status is '${status}'. No notification required.`);
      return new Response("Status does not require a rider notification.", { status: 200 });
    }

    console.log(`Sending '${titleText}' to Rider: ${riderId}`);

    // 4. Send to OneSignal
    const response = await fetch("https://onesignal.com/api/v1/notifications", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Basic ${ONESIGNAL_REST_API_KEY}`
      },
      body: JSON.stringify({
        app_id: ONESIGNAL_APP_ID,
        target_channel: "push",
        include_aliases: {
          external_id: [String(riderId)]
        },
        headings: { "en": titleText },
        contents: { "en": bodyText },
        data: {
          order_id: newRecord.id,
          status: status
        }
      })
    });

    const result = await response.json();
    console.log("OneSignal Response:", result);

    return new Response(JSON.stringify({ success: true, result }), {
      headers: { "Content-Type": "application/json" },
      status: 200,
    });

  } catch (error) {
    console.error("ERROR:", error.message);
    return new Response(JSON.stringify({ error: error.message }), { status: 500 });
  }
});