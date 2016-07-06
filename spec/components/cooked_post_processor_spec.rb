require "rails_helper"
require "cooked_post_processor"

describe CookedPostProcessor do

  context ".post_process" do

    let(:post) { build(:post) }
    let(:cpp) { CookedPostProcessor.new(post) }
    let(:post_process) { sequence("post_process") }

    it "post process in sequence" do
      cpp.expects(:keep_reverse_index_up_to_date).in_sequence(post_process)
      cpp.expects(:post_process_images).in_sequence(post_process)
      cpp.expects(:post_process_oneboxes).in_sequence(post_process)
      cpp.expects(:optimize_urls).in_sequence(post_process)
      cpp.expects(:pull_hotlinked_images).in_sequence(post_process)
      cpp.post_process
    end

  end

  context ".keep_reverse_index_up_to_date" do

    let(:post) { build(:post_with_uploads, id: 123) }
    let(:cpp) { CookedPostProcessor.new(post) }

    it "finds all the uploads in the post" do
      Upload.expects(:get_from_url).with("/uploads/default/2/2345678901234567.jpg")
      Upload.expects(:get_from_url).with("/uploads/default/1/1234567890123456.jpg")
      cpp.keep_reverse_index_up_to_date
    end

    it "cleans the reverse index up for the current post" do
      PostUpload.expects(:delete_all).with(post_id: post.id)
      cpp.keep_reverse_index_up_to_date
    end

  end

  context ".post_process_images" do

    shared_examples "leave dimensions alone" do
      it "doesn't use them" do
        # adds the width from the image sizes provided when no dimension is provided
        expect(cpp.html).to match(/src="http:\/\/foo.bar\/image.png" width="" height=""/)
        # adds the width from the image sizes provided
        expect(cpp.html).to match(/src="http:\/\/domain.com\/picture.jpg" width="50" height="42"/)
        expect(cpp).to be_dirty
      end
    end

    context "with image_sizes" do
      let(:post) { Fabricate(:post_with_image_urls) }
      let(:cpp) { CookedPostProcessor.new(post, image_sizes: image_sizes) }

      before { cpp.post_process_images }

      context "valid" do
        let(:image_sizes) { {"http://foo.bar/image.png" => {"width" => 111, "height" => 222}} }

        it "use them" do
          # adds the width from the image sizes provided when no dimension is provided
          expect(cpp.html).to match(/src="http:\/\/foo.bar\/image.png" width="111" height="222"/)
          # adds the width from the image sizes provided
          expect(cpp.html).to match(/src="http:\/\/domain.com\/picture.jpg" width="50" height="42"/)
          expect(cpp).to be_dirty
        end
      end

      context "invalid width" do
        let(:image_sizes) { {"http://foo.bar/image.png" => {"width" => 0, "height" => 222}} }
        include_examples "leave dimensions alone"
      end

      context "invalid height" do
        let(:image_sizes) { {"http://foo.bar/image.png" => {"width" => 111, "height" => 0}} }
        include_examples "leave dimensions alone"
      end

      context "invalid width & height" do
        let(:image_sizes) { {"http://foo.bar/image.png" => {"width" => 0, "height" => 0}} }
        include_examples "leave dimensions alone"
      end

    end

    context "with unsized images" do

      let(:post) { Fabricate(:post_with_unsized_images) }
      let(:cpp) { CookedPostProcessor.new(post) }

      it "adds the width and height to images that don't have them" do
        FastImage.expects(:size).returns([123, 456])
        cpp.post_process_images
        expect(cpp.html).to match(/width="123" height="456"/)
        expect(cpp).to be_dirty
      end

    end

    context "with large images" do

      let(:upload) { Fabricate(:upload) }
      let(:post) { Fabricate(:post_with_large_image) }
      let(:cpp) { CookedPostProcessor.new(post) }

      before do
        SiteSetting.max_image_height = 2000
        SiteSetting.create_thumbnails = true

        Upload.expects(:get_from_url).returns(upload)
        FastImage.stubs(:size).returns([1750, 2000])

        # hmmm this should be done in a cleaner way
        OptimizedImage.expects(:resize).returns(true)

        FileStore::BaseStore.any_instance.expects(:get_depth_for).returns(0)
      end

      it "generates overlay information" do
        cpp.post_process_images
        expect(cpp.html).to match_html "<p><div class=\"lightbox-wrapper\"><a data-download-href=\"/uploads/default/#{upload.sha1}\" href=\"/uploads/default/1/1234567890123456.jpg\" class=\"lightbox\" title=\"logo.png\"><img src=\"/uploads/default/optimized/1X/#{upload.sha1}_1_690x788.png\" width=\"690\" height=\"788\"><div class=\"meta\">
<span class=\"filename\">logo.png</span><span class=\"informations\">1750x2000 1.21 KB</span><span class=\"expand\"></span>
</div></a></div></p>"
        expect(cpp).to be_dirty
      end

    end

    context "with large images when using subfolders" do

      let(:upload) { Fabricate(:upload) }
      let(:post) { Fabricate(:post_with_large_image_on_subfolder) }
      let(:cpp) { CookedPostProcessor.new(post) }
      let(:base_url) { "http://test.localhost/subfolder" }
      let(:base_uri) { "/subfolder" }

      before do
        SiteSetting.max_image_height = 2000
        SiteSetting.create_thumbnails = true
        Discourse.stubs(:base_url).returns(base_url)
        Discourse.stubs(:base_uri).returns(base_uri)

        Upload.expects(:get_from_url).returns(upload)
        FastImage.stubs(:size).returns([1750, 2000])

        # hmmm this should be done in a cleaner way
        OptimizedImage.expects(:resize).returns(true)

        FileStore::BaseStore.any_instance.expects(:get_depth_for).returns(0)
      end

      it "generates overlay information" do
        cpp.post_process_images
        expect(cpp.html).to match_html "<p><div class=\"lightbox-wrapper\"><a data-download-href=\"/subfolder/uploads/default/#{upload.sha1}\" href=\"/subfolder/uploads/default/1/1234567890123456.jpg\" class=\"lightbox\" title=\"logo.png\"><img src=\"/subfolder/uploads/default/optimized/1X/#{upload.sha1}_1_690x788.png\" width=\"690\" height=\"788\"><div class=\"meta\">
<span class=\"filename\">logo.png</span><span class=\"informations\">1750x2000 1.21 KB</span><span class=\"expand\"></span>
</div></a></div></p>"
        expect(cpp).to be_dirty
      end

    end

    context "with title" do

      let(:upload) { Fabricate(:upload) }
      let(:post) { Fabricate(:post_with_large_image_and_title) }
      let(:cpp) { CookedPostProcessor.new(post) }

      before do
        SiteSetting.max_image_height = 2000
        SiteSetting.create_thumbnails = true

        Upload.expects(:get_from_url).returns(upload)
        FastImage.stubs(:size).returns([1750, 2000])

        # hmmm this should be done in a cleaner way
        OptimizedImage.expects(:resize).returns(true)
        FileStore::BaseStore.any_instance.expects(:get_depth_for).returns(0)
      end

      it "generates overlay information" do
        cpp.post_process_images
        expect(cpp.html).to match_html "<p><div class=\"lightbox-wrapper\"><a data-download-href=\"/uploads/default/#{upload.sha1}\" href=\"/uploads/default/1/1234567890123456.jpg\" class=\"lightbox\" title=\"WAT\"><img src=\"/uploads/default/optimized/1X/#{upload.sha1}_1_690x788.png\" title=\"WAT\" width=\"690\" height=\"788\"><div class=\"meta\">
       <span class=\"filename\">WAT</span><span class=\"informations\">1750x2000 1.21 KB</span><span class=\"expand\"></span>
       </div></a></div></p>"
        expect(cpp).to be_dirty
      end

    end

    context "topic image" do

      let(:topic) { build(:topic, id: 1) }
      let(:post) { Fabricate(:post_with_uploaded_image, topic: topic) }
      let(:cpp) { CookedPostProcessor.new(post) }

      it "adds a topic image if there's one in the post" do
        FastImage.stubs(:size)
        expect(post.topic.image_url).to eq(nil)
        cpp.post_process_images
        post.topic.reload
        expect(post.topic.image_url).to be_present
      end

    end

  end

  context ".extract_images" do

    let(:post) { build(:post_with_plenty_of_images) }
    let(:cpp) { CookedPostProcessor.new(post) }

    it "does not extract emojis or images inside oneboxes or quotes" do
      expect(cpp.extract_images.length).to eq(0)
    end

  end

  context ".get_size_from_attributes" do

    let(:post) { build(:post) }
    let(:cpp) { CookedPostProcessor.new(post) }

    it "returns the size when width and height are specified" do
      img = { 'src' => 'http://foo.bar/image3.png', 'width' => 50, 'height' => 70}
      expect(cpp.get_size_from_attributes(img)).to eq([50, 70])
    end

    it "returns the size when width and height are floats" do
      img = { 'src' => 'http://foo.bar/image3.png', 'width' => 50.2, 'height' => 70.1}
      expect(cpp.get_size_from_attributes(img)).to eq([50, 70])
    end

    it "resizes when only width is specified" do
      img = { 'src' => 'http://foo.bar/image3.png', 'width' => 100}
      SiteSetting.stubs(:crawl_images?).returns(true)
      FastImage.expects(:size).returns([200, 400])
      expect(cpp.get_size_from_attributes(img)).to eq([100, 200])
    end

    it "resizes when only height is specified" do
      img = { 'src' => 'http://foo.bar/image3.png', 'height' => 100}
      SiteSetting.stubs(:crawl_images?).returns(true)
      FastImage.expects(:size).returns([100, 300])
      expect(cpp.get_size_from_attributes(img)).to eq([33, 100])
    end

  end

  context ".get_size_from_image_sizes" do

    let(:post) { build(:post) }
    let(:cpp) { CookedPostProcessor.new(post) }

    it "returns the size" do
      image_sizes = { "http://my.discourse.org/image.png" => { "width" => 111, "height" => 222 } }
      expect(cpp.get_size_from_image_sizes("/image.png", image_sizes)).to eq([111, 222])
    end

  end

  context ".get_size" do

    let(:post) { build(:post) }
    let(:cpp) { CookedPostProcessor.new(post) }

    it "ensures urls are absolute" do
      cpp.expects(:is_valid_image_url?).with("http://test.localhost/relative/url/image.png")
      cpp.get_size("/relative/url/image.png")
    end

    it "ensures urls have a default scheme" do
      cpp.expects(:is_valid_image_url?).with("http://schemaless.url/image.jpg")
      cpp.get_size("//schemaless.url/image.jpg")
    end

    it "caches the results" do
      SiteSetting.stubs(:crawl_images?).returns(true)
      FastImage.expects(:size).returns([200, 400])
      cpp.get_size("http://foo.bar/image3.png")
      expect(cpp.get_size("http://foo.bar/image3.png")).to eq([200, 400])
    end

    context "when crawl_images is disabled" do

      before { SiteSetting.stubs(:crawl_images?).returns(false) }

      it "doesn't call FastImage" do
        FastImage.expects(:size).never
        expect(cpp.get_size("http://foo.bar/image1.png")).to eq(nil)
      end

      it "is always allowed to crawl our own images" do
        store = stub
        store.expects(:has_been_uploaded?).returns(true)
        Discourse.expects(:store).returns(store)
        FastImage.expects(:size).returns([100, 200])
        expect(cpp.get_size("http://foo.bar/image2.png")).to eq([100, 200])
      end

      it "returns nil if FastImage can't get the original size" do
        Discourse.store.class.any_instance.expects(:has_been_uploaded?).returns(true)
        FastImage.expects(:size).returns(nil)
        expect(cpp.get_size("http://foo.bar/image3.png")).to eq(nil)
      end

    end

  end

  context ".is_valid_image_url?" do

    let(:post) { build(:post) }
    let(:cpp) { CookedPostProcessor.new(post) }

    it "validates HTTP(s) urls" do
      expect(cpp.is_valid_image_url?("http://domain.com")).to eq(true)
      expect(cpp.is_valid_image_url?("https://domain.com")).to eq(true)
    end

    it "doesn't validate other urls" do
      expect(cpp.is_valid_image_url?("ftp://domain.com")).to eq(false)
      expect(cpp.is_valid_image_url?("ftps://domain.com")).to eq(false)
      expect(cpp.is_valid_image_url?("/tmp/image.png")).to eq(false)
      expect(cpp.is_valid_image_url?("//domain.com")).to eq(false)
    end

    it "doesn't throw an exception with a bad URI" do
      expect(cpp.is_valid_image_url?("http://do<main.com")).to eq(nil)
    end

  end

  context ".get_filename" do

    let(:post) { build(:post) }
    let(:cpp) { CookedPostProcessor.new(post) }

    it "returns the filename of the src when there is no upload" do
      expect(cpp.get_filename(nil, "http://domain.com/image.png")).to eq("image.png")
    end

    it "returns the original filename of the upload when there is an upload" do
      upload = build(:upload, { original_filename: "upload.jpg" })
      expect(cpp.get_filename(upload, "http://domain.com/image.png")).to eq("upload.jpg")
    end

    it "returns a generic name for pasted images" do
      upload = build(:upload, { original_filename: "blob.png" })
      expect(cpp.get_filename(upload, "http://domain.com/image.png")).to eq(I18n.t('upload.pasted_image_filename'))
    end

  end

  context ".post_process_oneboxes" do

    let(:post) { build(:post_with_youtube, id: 123) }
    let(:cpp) { CookedPostProcessor.new(post, invalidate_oneboxes: true) }

    before do
      Oneboxer.expects(:onebox)
              .with("http://www.youtube.com/watch?v=9bZkp7q19f0", post_id: 123, invalidate_oneboxes: true)
              .returns("<div>GANGNAM STYLE</div>")
      cpp.post_process_oneboxes
    end

    it "is dirty" do
      expect(cpp).to be_dirty
    end

    it "inserts the onebox without wrapping p" do
      expect(cpp.html).to match_html "<div>GANGNAM STYLE</div>"
    end

  end

  context ".optimize_urls" do

    let(:post) { build(:post_with_uploads_and_links) }
    let(:cpp) { CookedPostProcessor.new(post) }

    it "uses schemaless url for uploads" do
      cpp.optimize_urls
      expect(cpp.html).to match_html '<p><a href="//test.localhost/uploads/default/2/2345678901234567.jpg">Link</a><br><img src="//test.localhost/uploads/default/1/1234567890123456.jpg"><br><a href="http://www.google.com" rel="nofollow">Google</a><br><img src="http://foo.bar/image.png"><br><a class="attachment" href="//test.localhost/uploads/default/original/1X/af2c2618032c679333bebf745e75f9088748d737.txt">text.txt</a> (20 Bytes)</p>'
    end

    context "when CDN is enabled" do

      it "does use schemaless CDN url for http uploads" do
        Rails.configuration.action_controller.stubs(:asset_host).returns("http://my.cdn.com")
        cpp.optimize_urls
        expect(cpp.html).to match_html '<p><a href="//my.cdn.com/uploads/default/2/2345678901234567.jpg">Link</a><br><img src="//my.cdn.com/uploads/default/1/1234567890123456.jpg"><br><a href="http://www.google.com" rel="nofollow">Google</a><br><img src="http://foo.bar/image.png"><br><a class="attachment" href="//my.cdn.com/uploads/default/original/1X/af2c2618032c679333bebf745e75f9088748d737.txt">text.txt</a> (20 Bytes)</p>'
      end

      it "does not use schemaless CDN url for https uploads" do
        Rails.configuration.action_controller.stubs(:asset_host).returns("https://my.cdn.com")
        cpp.optimize_urls
        expect(cpp.html).to match_html '<p><a href="https://my.cdn.com/uploads/default/2/2345678901234567.jpg">Link</a><br><img src="https://my.cdn.com/uploads/default/1/1234567890123456.jpg"><br><a href="http://www.google.com" rel="nofollow">Google</a><br><img src="http://foo.bar/image.png"><br><a class="attachment" href="https://my.cdn.com/uploads/default/original/1X/af2c2618032c679333bebf745e75f9088748d737.txt">text.txt</a> (20 Bytes)</p>'
      end

      it "does not use CDN when login is required" do
        SiteSetting.login_required = true
        Rails.configuration.action_controller.stubs(:asset_host).returns("http://my.cdn.com")
        cpp.optimize_urls
        expect(cpp.html).to match_html '<p><a href="//my.cdn.com/uploads/default/2/2345678901234567.jpg">Link</a><br><img src="//my.cdn.com/uploads/default/1/1234567890123456.jpg"><br><a href="http://www.google.com" rel="nofollow">Google</a><br><img src="http://foo.bar/image.png"><br><a class="attachment" href="//test.localhost/uploads/default/original/1X/af2c2618032c679333bebf745e75f9088748d737.txt">text.txt</a> (20 Bytes)</p>'
      end

    end

  end

  context ".pull_hotlinked_images" do

    let(:post) { build(:post, created_at: 20.days.ago) }
    let(:cpp) { CookedPostProcessor.new(post) }

    before { cpp.stubs(:available_disk_space).returns(90) }

    it "does not run when download_remote_images_to_local is disabled" do
      SiteSetting.stubs(:download_remote_images_to_local).returns(false)
      Jobs.expects(:cancel_scheduled_job).never
      cpp.pull_hotlinked_images
    end

    context "when download_remote_images_to_local? is enabled" do

      before { SiteSetting.stubs(:download_remote_images_to_local).returns(true) }

      it "does not run when there is not enough disk space" do
        cpp.expects(:disable_if_low_on_disk_space).returns(true)
        Jobs.expects(:cancel_scheduled_job).never
        cpp.pull_hotlinked_images
      end

      context "and there is enough disk space" do

        before { cpp.expects(:disable_if_low_on_disk_space).returns(false) }

        it "does not run when the system user updated the post" do
          post.last_editor_id = Discourse.system_user.id
          Jobs.expects(:cancel_scheduled_job).never
          cpp.pull_hotlinked_images
        end

        context "and the post has been updated by an actual user" do

          before { post.id = 42 }

          it "ensures only one job is scheduled right after the editing_grace_period" do
            Jobs.expects(:cancel_scheduled_job).with(:pull_hotlinked_images, post_id: post.id).once

            delay = SiteSetting.editing_grace_period + 1
            Jobs.expects(:enqueue_in).with(delay.seconds, :pull_hotlinked_images, post_id: post.id, bypass_bump: false).once

            cpp.pull_hotlinked_images
          end

        end

      end

    end

  end

  context ".disable_if_low_on_disk_space" do

    let(:post) { build(:post, created_at: 20.days.ago) }
    let(:cpp) { CookedPostProcessor.new(post) }

    before { cpp.expects(:available_disk_space).returns(50) }

    it "does nothing when there's enough disk space" do
      SiteSetting.expects(:download_remote_images_threshold).returns(20)
      SiteSetting.expects(:download_remote_images_to_local).never
      expect(cpp.disable_if_low_on_disk_space).to eq(false)
    end

    context "when there's not enough disk space" do

      before { SiteSetting.expects(:download_remote_images_threshold).returns(75) }

      it "disables download_remote_images_threshold and send a notification to the admin" do
        StaffActionLogger.any_instance.expects(:log_site_setting_change).once
        SystemMessage.expects(:create_from_system_user).with(Discourse.site_contact_user, :download_remote_images_disabled).once
        expect(cpp.disable_if_low_on_disk_space).to eq(true)
        expect(SiteSetting.download_remote_images_to_local).to eq(false)
      end

    end

  end

  context ".download_remote_images_max_days_old" do

    let(:post) { build(:post, created_at: 20.days.ago) }
    let(:cpp) { CookedPostProcessor.new(post) }

    before do
      SiteSetting.download_remote_images_to_local = true
      cpp.expects(:disable_if_low_on_disk_space).returns(false)
    end

    it "does not run when download_remote_images_max_days_old is not satisfied" do
      SiteSetting.download_remote_images_max_days_old = 15
      Jobs.expects(:cancel_scheduled_job).never
      cpp.pull_hotlinked_images
    end

    it "runs when download_remote_images_max_days_old is satisfied" do
      SiteSetting.download_remote_images_max_days_old = 30

      Jobs.expects(:cancel_scheduled_job).with(:pull_hotlinked_images, post_id: post.id).once

      delay = SiteSetting.editing_grace_period + 1
      Jobs.expects(:enqueue_in).with(delay.seconds, :pull_hotlinked_images, post_id: post.id, bypass_bump: false).once

      cpp.pull_hotlinked_images
    end
  end

  context ".is_a_hyperlink?" do

    let(:post) { build(:post) }
    let(:cpp) { CookedPostProcessor.new(post) }
    let(:doc) { Nokogiri::HTML::fragment('<body><div><a><img id="linked_image"></a><p><img id="standard_image"></p></div></body>') }

    it "is true when the image is inside a link" do
      img = doc.css("img#linked_image").first
      expect(cpp.is_a_hyperlink?(img)).to eq(true)
    end

    it "is false when the image is not inside a link" do
      img = doc.css("img#standard_image").first
      expect(cpp.is_a_hyperlink?(img)).to eq(false)
    end

  end

  context "extracts links" do
      let(:post) { Fabricate(:post, raw: "sam has a blog at https://samsaffron.com") }
      it "always re-extracts links on post process" do
        TopicLink.destroy_all
        CookedPostProcessor.new(post).post_process
        expect(TopicLink.count).to eq(1)
      end
  end

  context "grant badges" do

    context "emoji inside a quote" do
      let(:post) { Fabricate(:post, raw: "time to eat some sweet [quote]:candy:[/quote] mmmm") }
      let(:cpp) { CookedPostProcessor.new(post) }

      it "doesn't award a badge when the emoji is in a quote" do
        cpp.grant_badges
        expect(post.user.user_badges.where(badge_id: Badge::FirstEmoji).exists?).to eq(false)
      end
    end

    context "emoji in the text" do
      let(:post) { Fabricate(:post, raw: "time to eat some sweet :candy: mmmm") }
      let(:cpp) { CookedPostProcessor.new(post) }

      it "awards a badge for using an emoji" do
        cpp.grant_badges
        expect(post.user.user_badges.where(badge_id: Badge::FirstEmoji).exists?).to eq(true)
      end
    end

    context "onebox" do
      let(:user) { Fabricate(:user) }
      let(:post) { Fabricate.build(:post, user: user, raw: "onebox me:\n\nhttps://www.youtube.com/watch?v=Wji-BZ0oCwg\n") }
      let(:cpp) { CookedPostProcessor.new(post) }

      before do
        Oneboxer.stubs(:onebox)
      end

      it "awards a badge for using an emoji" do
        cpp.post_process_oneboxes
        cpp.grant_badges
        expect(post.user.user_badges.where(badge_id: Badge::FirstOnebox).exists?).to eq(true)
      end
    end

  end

end
