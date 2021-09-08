# frozen_string_literal: true

require 'rails_helper'

describe BookmarksController do
  let(:current_user) { Fabricate(:user) }
  let(:bookmark_post) { Fabricate(:post) }
  let(:bookmark_user) { current_user }

  before do
    sign_in(current_user)
  end

  describe "#create" do
    it "creates a bookmark for a post" do
      post "/bookmarks.json", params: {
        post_id: bookmark_post.id,
        reminder_type: "tomorrow",
        reminder_at: (Time.zone.now + 1.day).iso8601
      }

      expect(response.status).to eq(200)
      expect(Bookmark.exists?(user: bookmark_user, post: bookmark_post)).to eq(true)
    end

    it "creates a bookmark for the topic" do
      post "/bookmarks.json", params: {
        post_id: nil,
        topic_id: bookmark_post.topic.id,
        reminder_type: "tomorrow",
        reminder_at: (Time.zone.now + 1.day).iso8601
      }

      expect(response.status).to eq(200)
      expect(
        Bookmark.exists?(
          user: bookmark_user, post_id: nil, topic_id: bookmark_post.topic.id
        )
      ).to eq(true)
    end

    it "rate limits creates" do
      SiteSetting.max_bookmarks_per_day = 1
      RateLimiter.enable
      RateLimiter.clear_all!

      post "/bookmarks.json", params: {
        post_id: bookmark_post.id,
        reminder_type: "tomorrow",
        reminder_at: (Time.zone.now + 1.day).iso8601
      }

      expect(response.status).to eq(200)

      post "/bookmarks.json", params: {
        post_id: Fabricate(:post).id
      }
      expect(response.status).to eq(429)
    end

    context "if the user reached the max bookmark limit" do
      before do
        SiteSetting.max_bookmarks_per_user = 1
      end

      it "returns failed JSON with a 400 error" do
        post "/bookmarks.json", params: {
          post_id: bookmark_post.id,
          reminder_type: "tomorrow",
          reminder_at: (Time.zone.now + 1.day).iso8601
        }
        post "/bookmarks.json", params: {
          post_id: Fabricate(:post).id
        }

        expect(response.status).to eq(400)
        user_bookmarks_url = "#{Discourse.base_url}/my/activity/bookmarks"
        expect(response.parsed_body['errors']).to include(
          I18n.t("bookmarks.errors.too_many", user_bookmarks_url: user_bookmarks_url, limit: SiteSetting.max_bookmarks_per_user)
        )
      end
    end

    context "if the user already has bookmarked the post" do
      before do
        Fabricate(:bookmark, post: bookmark_post, user: bookmark_user)
      end

      it "returns failed JSON with a 400 error" do
        post "/bookmarks.json", params: {
          post_id: bookmark_post.id,
          reminder_type: "tomorrow",
          reminder_at: (Time.zone.now + 1.day).iso8601
        }

        expect(response.status).to eq(400)
        expect(response.parsed_body['errors']).to include(
          I18n.t("bookmarks.errors.already_bookmarked_post")
        )
      end
    end

    context "if the user provides a reminder type that needs a reminder_at that is missing" do
      it "returns failed JSON with a 400 error" do
        post "/bookmarks.json", params: {
          post_id: bookmark_post.id,
          reminder_type: "tomorrow"
        }

        expect(response.status).to eq(400)
        expect(response.parsed_body['errors'].first).to include(
          I18n.t("bookmarks.errors.time_must_be_provided")
        )
      end
    end
  end

  describe "#destroy" do
    let!(:bookmark) { Fabricate(:bookmark, post: bookmark_post, user: bookmark_user) }

    it "destroys the bookmark" do
      delete "/bookmarks/#{bookmark.id}.json"
      expect(Bookmark.find_by(id: bookmark.id)).to eq(nil)
    end

    context "if the bookmark has already been destroyed" do
      it "returns failed JSON with a 403 error" do
        bookmark.destroy!
        delete "/bookmarks/#{bookmark.id}.json"

        expect(response.status).to eq(404)
        expect(response.parsed_body['errors'].first).to include(
          I18n.t("not_found")
        )
      end
    end

    context "if the bookmark does not belong to the user" do
      let(:bookmark_user) { Fabricate(:user) }

      it "returns failed JSON with a 403 error" do
        delete "/bookmarks/#{bookmark.id}.json"

        expect(response.status).to eq(403)
        expect(response.parsed_body['errors'].first).to include(
          I18n.t("invalid_access")
        )
      end
    end
  end
end
