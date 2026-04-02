import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

serve(async (req) => {
  try {
    const payload = await req.json();
    const newRecord = payload.record;
    const oldRecord = payload.old_record || {};

    console.log(`Webhook triggered for Order ID: ${newRecord.id}`);

    // 1. SMART CHECK
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

    // ⚠️ PASTE YOUR EXACT KEYS INSIDE THE QUOTES BELOW:
   const ONESIGNAL_APP_ID = "98573413-e76f-4636-9442-40cce7f1e70e";
    const ONESIGNAL_REST_API_KEY = "os_v2_app_tbltie7hn5ddnfccidgop4phbzzojxruownutrentkfjvytww7j4k4aesmwnhxkgypagmwxwtevei4rrce4liafttov52perm4xbkgi";

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
      shouldNotify = false;
    }

    if (!shouldNotify) {
      console.log(`Status is '${status}'. No notification required.`);
      return new Response("Status does not require a rider notification.", { status: 200 });
    }

    console.log(`Sending '${titleText}' to Rider: ${riderId}`);

    // DEBUG LOGS TO VERIFY KEYS
    console.log(`DEBUG APP ID: ${ONESIGNAL_APP_ID}`);
    console.log(`DEBUG API KEY: ${String(ONESIGNAL_REST_API_KEY).substring(0, 5)}...`);

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