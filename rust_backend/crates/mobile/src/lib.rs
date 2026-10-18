//! Native APIs for the local, offline Android player.

mod cancellation;
mod data_jobs;
mod filename;
mod hires;
mod library_metadata;
mod local;
mod logging;
mod lyrics;
mod native_backup;
mod native_cache;
mod native_collections;
mod native_id3;
mod native_library;
mod native_lyrics;
mod native_playlist_write;
mod native_playlists;
mod native_xml;
mod tags;
mod usb_audio;

uniffi::setup_scaffolding!();

#[uniffi::export]
pub fn sanitize_filename(filename: String) -> String {
    spotiflac_core::filename::sanitize_filename(&filename)
}
