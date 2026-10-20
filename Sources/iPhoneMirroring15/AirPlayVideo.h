#include <stdint.h>

typedef struct AirPlayVideoReceiver AirPlayVideoReceiver;
typedef void (*AirPlayVideoFrameCallback)(const uint8_t *bytes, int width, int height, int stride, void *context);
typedef void (*AirPlayVideoErrorCallback)(const char *message, void *context);

AirPlayVideoReceiver *airplay_video_start(AirPlayVideoFrameCallback frame_callback,
                                          AirPlayVideoErrorCallback error_callback,
                                          void *context,
                                          int *port,
                                          char **error_message);
void airplay_video_stop(AirPlayVideoReceiver *receiver);
void airplay_video_free_error(char *error_message);
