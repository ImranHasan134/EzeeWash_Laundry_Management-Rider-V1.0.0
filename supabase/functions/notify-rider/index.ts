import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

serve(async (req) => {
  try {
    const payload = await req.json();
    const newRecord = payload.record;

    const riderId = newRecord.rider_id || newRecord.pickup_rider_id || newRecord.delivery_rider_id;

    if (!riderId) {
      return new Response("No rider assigned, ignoring.", { status: 200 });
    }

    const ONESIGNAL_APP_ID = Deno.env.get("ONESIGNAL_APP_ID") ?? "";
    const ONESIGNAL_REST_API_KEY = Deno.env.get("ONESIGNAL_REST_API_KEY") ?? "";

    // --- SMART STATUS CHECKER ---
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
      // If it's any other status (like 'pending'), don't spam the rider with notifications
      shouldNotify = false;
    }

    // Stop the function if no notification is needed
    if (!shouldNotify) {
      return new Response("Status does not require a rider notification.", { status: 200 });
    }

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
        }
      })
    });

    const result = await response.json();
    return new Response(JSON.stringify({ success: true, result }), {
      headers: { "Content-Type": "application/json" },
    });

  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), { status: 500 });
  }
});