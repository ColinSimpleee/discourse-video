/* global Hls */
import { ajax } from "discourse/lib/ajax";
import { renderIcon } from "discourse/lib/icon-library";
import loadScript from "discourse/lib/load-script";
import { withPluginApi } from "discourse/lib/plugin-api";
import { i18n } from "discourse-i18n";
import DiscourseVideoUploadForm from "../components/modal/discourse-video-upload-form";

const HLS_SCRIPT_URL = "/plugins/discourse-video/javascripts/hls.min.js";
const MUX_PLAYER_URL = "https://cdn.jsdelivr.net/npm/@mux/mux-player";

function initializeDiscourseVideo(api) {
  const siteSettings = api.container.lookup("service:site-settings");
  const modal = api.container.lookup("service:modal");
  const user = api.getCurrentUser();

  function renderVideo(videoContainer, videoId) {
    if (!videoContainer || !videoId) {
      return;
    }

    loadScript(MUX_PLAYER_URL).then(() => {
      ajax(`/discourse_video/playback_id/${videoId}`).then((data) => {
        if (!data.playback_id) {
          renderPlaceholder(videoContainer, "pending");
          return;
        }

        let muxPlayer = document.createElement("mux-player");
        muxPlayer.setAttribute("playback-id", data.playback_id);
        muxPlayer.setAttribute("stream-type", "on-demand");
        muxPlayer.setAttribute("controls", true);
        muxPlayer.setAttribute("accent-color", "#FF4800");
        muxPlayer.className = "mux-video";

        let placeholder = videoContainer.querySelector(".icon-container");
        if (placeholder) {
          videoContainer.replaceChild(muxPlayer, placeholder);
        } else {
          videoContainer.appendChild(muxPlayer);
        }
      });
    });
  }

  function renderVideoDownloadLink(videoContainer, videoId) {
    loadScript(HLS_SCRIPT_URL).then(() => {
      ajax(`/discourse_video/playback_id/${videoId}`).then((data) => {
        let downloadLink = document.createElement("a");
        let text = document.createTextNode(
          i18n("discourse_video.download_video")
        );
        downloadLink.className = "download-mux-video";
        downloadLink.appendChild(text);
        const mp4Url = `https://stream.mux.com/${data.playback_id}/${data.mp4_filename}?download=${data.playback_id}.mp4`;
        downloadLink.href = mp4Url;

        if (data.mp4_filename) {
          videoContainer.appendChild(downloadLink);
        }
      });
    });
  }

  const placeholders = {
    pending: {
      iconHtml: "<div class='spinner'></div>",
      string: i18n("discourse_video.state.pending"),
    },
    waiting: {
      iconHtml: "<div class='spinner'></div>",
      string: i18n("discourse_video.state.pending"),
    },
    errored: {
      iconHtml: renderIcon("string", "triangle-exclamation"),
      string: i18n("discourse_video.state.errored"),
    },
    unknown: {
      iconHtml: renderIcon("string", "circle-question"),
      string: i18n("discourse_video.state.unknown"),
    },
  };

  function renderPlaceholder(container, type) {
    let iconContainerDiv = document.createElement("div");
    iconContainerDiv.className = "icon-container";

    let discourseVideoMessageDiv = document.createElement("div");
    discourseVideoMessageDiv.className = "discourse-video-message";
    iconContainerDiv.appendChild(discourseVideoMessageDiv);

    let videoStateIcon = document.createElement("div");
    videoStateIcon.className = "video-state-icon";
    videoStateIcon.innerHTML = `${placeholders[type].iconHtml}`;
    discourseVideoMessageDiv.appendChild(videoStateIcon);

    let videoState = document.createElement("div");
    videoState.className = "video-state";
    videoState.innerHTML = `${placeholders[type].string}`;
    discourseVideoMessageDiv.appendChild(videoState);

    let placeholder = container.querySelector(".icon-container");
    if (placeholder) {
      container.replaceChild(iconContainerDiv, placeholder);
    } else {
      container.appendChild(iconContainerDiv);
    }
  }

  function renderVideos(elem, post) {
    elem.querySelectorAll("div[data-video-id]").forEach(function (container) {
      const videoId = container.getAttribute("data-video-id").toString();
      if (!post.discourse_video || !videoId) {
        return;
      }

      post.discourse_video.forEach((video_string) => {
        if (video_string) {
          const status = video_string.replace(`${videoId}:`, "");
          if (status === "ready") {
            renderVideo(container, videoId);
          } else if (status === "errored") {
            renderPlaceholder(container, "errored");
          } else if (status === "waiting") {
            renderPlaceholder(container, "waiting");
          } else {
            renderPlaceholder(container, "pending");
          }
        } else {
          renderPlaceholder(container, "waiting");
        }
      });
    });

    elem
      .querySelectorAll("div[data-download-video-id]")
      .forEach(function (container) {
        const videoId = container
          .getAttribute("data-download-video-id")
          .toString();
        if (!post.discourse_video || !videoId) {
          return;
        }

        post.discourse_video.forEach((video_string) => {
          if (video_string) {
            const status = video_string.replace(`${videoId}:`, "");
            if (status === "ready") {
              renderVideoDownloadLink(container, videoId);
            }
          }
        });
      });
  }

  api.decorateCookedElement(
    (elem, helper) => {
      if (helper) {
        const post = helper.getModel();
        renderVideos(elem, post);
      } else {
        elem
          .querySelectorAll("div[data-video-id]")
          .forEach(function (container) {
            container.innerHTML = `<p><div class="onebox-placeholder-container">
            <span class="placeholder-icon video"></span>
          </div></p>`;
          });
      }
    },
    { id: "discourse-video" }
  );

  api.decorateChatMessage?.((elem) => {
    elem.querySelectorAll("div[data-video-id]").forEach(function (container) {
      const videoId = container.getAttribute("data-video-id").toString();
      if (!videoId) {
        return;
      }

      renderVideo(container, videoId);
    });
  });

  if (user && user.can_upload_video) {
    api.registerCustomPostMessageCallback(
      "discourse_video_video_changed",
      (topicController, message) => {
        let stream = topicController.get("model.postStream");
        const post = stream.findLoadedPost(message.id);

        stream.triggerChangedPost(message.id).then(() => {
          const elements = document.querySelectorAll("article[data-post-id]");
          elements.forEach(function (elem) {
            if (elem.getAttribute("data-post-id") === message.id.toString()) {
              renderVideos(elem, post);
            }
          });
        });
      }
    );

    api.addComposerUploadHandler(
      siteSettings.discourse_video_file_extensions.split("|"),
      (files) => {
        const file = Array.isArray(files) ? files[0] : files;
        modal.show(DiscourseVideoUploadForm, { model: { file } });
      }
    );

    api.onToolbarCreate((toolbar) => {
      toolbar.addButton({
        id: "discourse-video-upload",
        group: "insertions",
        icon: "video",
        title: "discourse_video.upload_toolbar_title",
        perform: () => modal.show(DiscourseVideoUploadForm),
      });
    });

    api.registerChatComposerButton?.({
      id: "discourse-video-upload",
      icon: "video",
      label: "discourse_video.upload_toolbar_title",
      position: "dropdown",
      action() {
        modal.show(DiscourseVideoUploadForm, {
          model: {
            afterUploadComplete: (videoTag) =>
              this.addText(this.getSelected(), videoTag),
          },
        });
      },
    });
  }
}

export default {
  name: "discourse-video",

  initialize(container) {
    const siteSettings = container.lookup("service:site-settings");

    if (siteSettings.discourse_video_enabled) {
      withPluginApi("0.8.31", initializeDiscourseVideo);
    }
  },
};
