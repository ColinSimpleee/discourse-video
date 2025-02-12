import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import { service } from "@ember/service";
import { on } from "@ember/modifier";
import { Promise } from "rsvp";
import DButton from "discourse/components/d-button";
import DModal from "discourse/components/d-modal";
import dIcon from "discourse/helpers/d-icon";
import { ajax } from "discourse/lib/ajax";
import { popupAjaxError } from "discourse/lib/ajax-error";
import { i18n } from "discourse-i18n";
import not from "truth-helpers/helpers/not";

const UPCHUNK = window.UpChunk;

export default class DiscourseVideoUploadForm extends Component {
  @service dialog;
  @service appEvents;
  @service siteSettings;
  @service currentUser;

  @tracked file = this.args.model?.file || null;
  @tracked videoDurationMinutes = null;
  @tracked uploadProgress;
  @tracked videoInfo;
  @tracked uploading = false;
  @tracked isDragging = false;

  afterUploadComplete = this.args.model?.afterUploadComplete || null;

  get fileSize() {
    return this.humanFilesize(this.file.size);
  }

  get isDurationAllowed() {
    if (this.currentUser.staff || this.videoDurationMinutes === null) {
      return true;
    }

    return (
      this.videoDurationMinutes < this.maxVideoDurationMinutes &&
      this.currentUser.trust_level === 4
    );
  }

  get maxVideoDurationMinutes() {
    return this.currentUser.trust_level === 4
      ? this.siteSettings.discourse_video_max_duration_minutes_leaders
      : this.siteSettings.discourse_video_max_duration_minutes;
  }

  @action
  async fileChanged(event) {
    const file = event.target.files[0];
    this.file = file;
    const duration = await this.getVideoDuration(file);
    this.videoDurationMinutes = this.durationMinutes(duration);
  }

  @action
  upload() {
    if (this.isAuthorizedVideo(this.file.name) && this.file.size > 0) {
      this.isDurationAllowed
        ? this.createVideoObject()
        : this.dialog.alert(
            !this.maxVideoDurationMinutes
              ? i18n("discourse_video.post.errors.duration_error")
              : i18n("discourse_video.post.errors.allowed_duration_exceeded", {
                  allowed_duration: this.maxVideoDurationMinutes,
                })
          );
    } else {
      this.dialog.alert(
        i18n("discourse_video.post.errors.upload_not_authorized", {
          authorized_extensions: this.videoExtensionsToArray().join(", "),
        })
      );
    }
  }

  @action
  async getVideoDuration(file) {
    return new Promise((resolve, reject) => {
      let video = document.createElement("video");
      video.preload = "metadata";

      video.onloadedmetadata = () => {
        resolve(video.duration);
      };

      video.onerror = () => {
        reject("Error processing video file");
      };

      video.src = URL.createObjectURL(file);
    });
  }

  @action
  async createVideoObject() {
    try {
      this.uploading = true;
      this.setProgress("preparing");
      const videoInfo = await ajax("/discourse_video/create", {
        type: "POST",
        data: { filename: this.file.name },
      });
      this.setupUpChunk(videoInfo);
    } catch (reason) {
      this.uploading = false;
      this.setProgress("error");
      popupAjaxError(reason);
    }
  }

  setProgress(key, args) {
    this.uploadProgress = i18n(`discourse_video.upload_progress.${key}`, args);
  }

  setupUpChunk(videoInfo) {
    this.setProgress("starting");
    this.videoInfo = videoInfo;

    const upload = UPCHUNK.createUpload({
      endpoint: videoInfo["api_request_url"],
      file: this.file,
      chunkSize: 5120, // Uploads the file in ~5mb chunks
    });

    upload.on("progress", (progress) => {
      this.setProgress("uploading", {
        progress: progress.detail.toFixed(1),
      });
    });

    upload.on("success", () => {
      this.uploadComplete();
    });
  }

  uploadComplete() {
    const videoInfo = this.videoInfo;
    this.setProgress("complete", { info: `[video=${videoInfo["video_id"]}]` });
    let videoTag = `[video=${videoInfo["video_id"]}]`;
    if (this.siteSettings.discourse_video_enable_mp4_download === true) {
      videoTag += ` [download-video=${videoInfo["video_id"]}]`;
    }

    if (this.afterUploadComplete) {
      this.afterUploadComplete(videoTag);
    } else {
      this.appEvents.trigger("composer:insert-text", videoTag);
    }
    this.args.closeModal();
  }

  videoExtensionsToArray() {
    return this.siteSettings.discourse_video_file_extensions
      .toLowerCase()
      .replace(/[\s\.]+/g, "")
      .split("|")
      .filter((ext) => !ext.includes("*"));
  }

  isAuthorizedVideo(fileName) {
    return new RegExp(
      `\\.(${this.videoExtensionsToArray().join("|")})$`,
      "i"
    ).test(fileName);
  }

  durationMinutes(duration) {
    return parseInt(duration / 60, 10);
  }

  humanFilesize(size) {
    let i = size === 0 ? 0 : Math.floor(Math.log(size) / Math.log(1024));
    return (
      (size / Math.pow(1024, i)).toFixed(2) * 1 +
      " " +
      ["B", "kB", "MB", "GB", "TB"][i]
    );
  }

  @action
  handleDragEnter(event) {
    event.preventDefault();
    event.stopPropagation();
    this.isDragging = true;
  }

  @action
  handleDragLeave(event) {
    event.preventDefault();
    event.stopPropagation();
    this.isDragging = false;
  }

  @action
  handleDrop(event) {
    event.preventDefault();
    event.stopPropagation();
    this.isDragging = false;
    const file = event.dataTransfer.files[0];
    if (file) {
      this.file = file;
      this.getVideoDuration(file).then((duration) => {
        this.videoDurationMinutes = this.durationMinutes(duration);
      });
    }
  }

  @action
  triggerFileInput() {
    document.getElementById("video-upload-input").click();
  }

  get acceptedVideoTypes() {
    return this.videoExtensionsToArray()
      .map((ext) => `.${ext}`)
      .join(",");
  }

  <template>
    <DModal
      @title={{i18n "discourse_video.modal_title"}}
      @subtitle={{i18n "discourse_video.modal_subtitle"}}
      class="discourse-video-upload-modal"
      @closeModal={{@closeModal}}
    >
      <:body>
        <div
          class="upload-area {{if this.isDragging 'is-dragging'}}"
          {{on "dragenter" this.handleDragEnter}}
          {{on "dragleave" this.handleDragLeave}}
          {{on "dragover" this.handleDragEnter}}
          {{on "drop" this.handleDrop}}
          {{on "click" this.triggerFileInput}}
          role="button"
        >
          {{#if this.file}}
            <p class="file-info">
              {{this.file.name}}
              ({{this.fileSize}})
            </p>
          {{else}}
            <div class="upload-prompt">
              {{dIcon "upload"}}
              <div class="upload-prompt-text">Click or drag to upload your video</div>
              <div class="upload-formats">Supported file formats:  MP4, MOV</div>
              <div class="upload-size-limit">Max file size: 10MB per image, 200M per video</div>
            </div>
          {{/if}}
          <input
            type="file"
            id="video-upload-input"
            class="file-input"
            disabled={{this.uploading}}
            accept={{this.acceptedVideoTypes}}
            onchange={{this.fileChanged}}
          />
        </div>
      </:body>
      <:footer>
        {{#if this.uploading}}
          {{this.uploadProgress}}
        {{else}}
          <DButton
            @action={{this.upload}}
            @icon="upload"
            @label="upload"
            @disabled={{not this.file}}
          />
        {{/if}}
      </:footer>
    </DModal>
  </template>
}
