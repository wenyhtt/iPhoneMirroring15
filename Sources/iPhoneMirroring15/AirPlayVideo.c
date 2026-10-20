#include "AirPlayVideo.h"

#include <gst/app/gstappsink.h>
#include <gst/video/video.h>
#include <gio/gio.h>

struct AirPlayVideoReceiver {
    GstElement *pipeline;
    GstAppSink *sink;
    GSocket *socket;
    GThread *bus_thread;
    AirPlayVideoFrameCallback frame_callback;
    AirPlayVideoErrorCallback error_callback;
    void *context;
    gint stopping;
};

static void set_error(char **output, const char *message) {
    if (output) *output = g_strdup(message);
}

static GstFlowReturn receive_sample(GstAppSink *sink, gpointer user_data) {
    AirPlayVideoReceiver *receiver = user_data;
    GstSample *sample = gst_app_sink_pull_sample(sink);
    if (!sample) return GST_FLOW_EOS;

    GstCaps *caps = gst_sample_get_caps(sample);
    GstVideoInfo info;
    GstBuffer *buffer = gst_sample_get_buffer(sample);
    GstMapInfo map;
    if (caps && buffer && gst_video_info_from_caps(&info, caps) && gst_buffer_map(buffer, &map, GST_MAP_READ)) {
        receiver->frame_callback(map.data,
                                 (int)GST_VIDEO_INFO_WIDTH(&info),
                                 (int)GST_VIDEO_INFO_HEIGHT(&info),
                                 (int)GST_VIDEO_INFO_PLANE_STRIDE(&info, 0),
                                 receiver->context);
        gst_buffer_unmap(buffer, &map);
    }
    gst_sample_unref(sample);
    return GST_FLOW_OK;
}

static gpointer watch_bus(gpointer user_data) {
    AirPlayVideoReceiver *receiver = user_data;
    GstBus *bus = gst_element_get_bus(receiver->pipeline);
    while (!g_atomic_int_get(&receiver->stopping)) {
        GstMessage *message = gst_bus_timed_pop_filtered(
            bus, 100 * GST_MSECOND, GST_MESSAGE_ERROR | GST_MESSAGE_EOS);
        if (!message) continue;
        if (GST_MESSAGE_TYPE(message) == GST_MESSAGE_ERROR) {
            GError *error = NULL;
            gchar *debug = NULL;
            gst_message_parse_error(message, &error, &debug);
            if (receiver->error_callback) receiver->error_callback(error ? error->message : "GStreamer playback failed", receiver->context);
            g_clear_error(&error);
            g_free(debug);
            gst_message_unref(message);
            break;
        }
        gst_message_unref(message);
        break;
    }
    gst_object_unref(bus);
    return NULL;
}

AirPlayVideoReceiver *airplay_video_start(AirPlayVideoFrameCallback frame_callback,
                                          AirPlayVideoErrorCallback error_callback,
                                          void *context,
                                          int *port,
                                          char **error_message) {
    static gsize initialized = 0;
    if (g_once_init_enter(&initialized)) {
        gst_init(NULL, NULL);
        g_once_init_leave(&initialized, 1);
    }

    GError *error = NULL;
    GInetAddress *address = g_inet_address_new_from_string("127.0.0.1");
    GSocketAddress *socket_address = g_inet_socket_address_new(address, 0);
    GSocket *socket = g_socket_new(G_SOCKET_FAMILY_IPV4, G_SOCKET_TYPE_DATAGRAM, G_SOCKET_PROTOCOL_UDP, &error);
    if (!socket || !g_socket_bind(socket, socket_address, TRUE, &error)) {
        set_error(error_message, error ? error->message : "Could not bind the local video receiver");
        g_clear_error(&error);
        if (socket) g_object_unref(socket);
        g_object_unref(socket_address);
        g_object_unref(address);
        return NULL;
    }
    GSocketAddress *bound_address = g_socket_get_local_address(socket, &error);
    if (!bound_address) {
        set_error(error_message, error ? error->message : "Could not read the local video port");
        g_clear_error(&error);
        g_object_unref(socket);
        g_object_unref(socket_address);
        g_object_unref(address);
        return NULL;
    }
    *port = (int)g_inet_socket_address_get_port(G_INET_SOCKET_ADDRESS(bound_address));
    g_object_unref(bound_address);
    g_object_unref(socket_address);
    g_object_unref(address);

    AirPlayVideoReceiver *receiver = g_new0(AirPlayVideoReceiver, 1);
    receiver->frame_callback = frame_callback;
    receiver->error_callback = error_callback;
    receiver->context = context;
    receiver->socket = socket;
    receiver->pipeline = gst_pipeline_new("airplay-video");

    GstElement *source = gst_element_factory_make("udpsrc", "source");
    GstElement *depay = gst_element_factory_make("rtph264depay", "depay");
    GstElement *parse = gst_element_factory_make("h264parse", "parse");
    GstElement *decode = gst_element_factory_make("avdec_h264", "decode");
    GstElement *convert = gst_element_factory_make("videoconvert", "convert");
    GstElement *filter = gst_element_factory_make("capsfilter", "format");
    GstElement *sink_element = gst_element_factory_make("appsink", "sink");
    if (!receiver->pipeline || !source || !depay || !parse || !decode || !convert || !filter || !sink_element) {
        set_error(error_message, "GStreamer is missing a required RTP, H.264 decoder, or video plugin");
        if (receiver->pipeline) gst_object_unref(receiver->pipeline);
        if (source) gst_object_unref(source);
        if (depay) gst_object_unref(depay);
        if (parse) gst_object_unref(parse);
        if (decode) gst_object_unref(decode);
        if (convert) gst_object_unref(convert);
        if (filter) gst_object_unref(filter);
        if (sink_element) gst_object_unref(sink_element);
        g_object_unref(socket);
        g_free(receiver);
        return NULL;
    }

    GstCaps *rtp_caps = gst_caps_from_string("application/x-rtp,media=video,clock-rate=90000,encoding-name=H264,payload=96");
    GstCaps *video_caps = gst_caps_from_string("video/x-raw,format=BGRA");
    g_object_set(source, "socket", socket, "close-socket", FALSE, "caps", rtp_caps, NULL);
    g_object_set(filter, "caps", video_caps, NULL);
    g_object_set(sink_element, "emit-signals", FALSE, "sync", FALSE, "max-buffers", 1, "drop", TRUE, NULL);
    gst_caps_unref(rtp_caps);
    gst_caps_unref(video_caps);

    gst_bin_add_many(GST_BIN(receiver->pipeline), source, depay, parse, decode, convert, filter, sink_element, NULL);
    if (!gst_element_link_many(source, depay, parse, decode, convert, filter, sink_element, NULL)) {
        set_error(error_message, "Could not link the GStreamer AirPlay video pipeline");
        gst_object_unref(receiver->pipeline);
        g_object_unref(socket);
        g_free(receiver);
        return NULL;
    }

    receiver->sink = GST_APP_SINK(sink_element);
    GstAppSinkCallbacks callbacks = {0};
    callbacks.new_sample = receive_sample;
    gst_app_sink_set_callbacks(receiver->sink, &callbacks, receiver, NULL);
    if (gst_element_set_state(receiver->pipeline, GST_STATE_PLAYING) == GST_STATE_CHANGE_FAILURE) {
        set_error(error_message, "GStreamer could not start the AirPlay video pipeline");
        gst_element_set_state(receiver->pipeline, GST_STATE_NULL);
        gst_object_unref(receiver->pipeline);
        g_object_unref(socket);
        g_free(receiver);
        return NULL;
    }
    receiver->bus_thread = g_thread_new("airplay-video-bus", watch_bus, receiver);
    return receiver;
}

void airplay_video_stop(AirPlayVideoReceiver *receiver) {
    if (!receiver) return;
    g_atomic_int_set(&receiver->stopping, 1);
    gst_element_set_state(receiver->pipeline, GST_STATE_NULL);
    if (receiver->bus_thread) g_thread_join(receiver->bus_thread);
    gst_object_unref(receiver->pipeline);
    g_object_unref(receiver->socket);
    g_free(receiver);
}

void airplay_video_free_error(char *error_message) {
    g_free(error_message);
}
