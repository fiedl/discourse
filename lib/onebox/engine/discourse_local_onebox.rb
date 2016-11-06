module Onebox
  module Engine
    class DiscourseLocalOnebox
      include Engine

      # Use this onebox before others
      def self.priority
        1
      end

      def self.===(other)
        url = other.to_s
        return false unless url[Discourse.base_url]

        path = url.sub(Discourse.base_url, "")
        route = Rails.application.routes.recognize_path(path)

        !!(route[:controller] =~ /topics|uploads/)
      rescue ActionController::RoutingError
        false
      end

      def to_html
        path = @url.sub(Discourse.base_url, "")
        route = Rails.application.routes.recognize_path(path)

        case route[:controller]
        when "uploads" then upload_html(path)
        when "topics"  then topic_html(path, route)
        end
      end

      private

        def upload_html(path)
          case File.extname(path)
          when /^\.(mov|mp4|webm|ogv)$/
            "<video width='100%' height='100%' controls><source src='#{@url}'><a href='#{@url}'>#{@url}</a></video>"
          when /^\.(mp3|ogg|wav)$/
            "<audio controls><source src='#{@url}'><a href='#{@url}'>#{@url}</a></audio>"
          end
        end

        def topic_html(path, route)
          link = "<a href='#{@url}'>#{@url}</a>"
          source_topic_id = @url[/[&?]source_topic_id=(\d+)/, 1].to_i

          if route[:post_number].present? && route[:post_number].to_i > 1
            post = Post.find_by(topic_id: route[:topic_id], post_number: route[:post_number])
            return link if post.nil? || post.hidden || !Guardian.new.can_see?(post)

            topic = post.topic
            slug = Slug.for(topic.title)
            excerpt = post.excerpt(SiteSetting.post_onebox_maxlength)
            excerpt.gsub!(/[\r\n]+/, " ")
            excerpt.gsub!("[/quote]", "[quote]") # don't break my quote

            quote = "[quote=\"#{post.user.username}, topic:#{topic.id}, slug:#{slug}, post:#{post.post_number}\"]#{excerpt}[/quote]"

            args = {}
            args[:topic_id] = source_topic_id if source_topic_id > 0

            PrettyText.cook(quote, args)
          else
            topic = Topic.find_by(id: route[:topic_id])
            return link if topic.nil? || !Guardian.new.can_see?(topic)

            first_post = topic.ordered_posts.first

            args = {
              topic: topic.id,
              avatar: PrettyText.avatar_img(topic.user.avatar_template, "tiny"),
              original_url: @url,
              title: PrettyText.unescape_emoji(CGI::escapeHTML(topic.title)),
              category_html: CategoryBadge.html_for(topic.category),
              quote: first_post.excerpt(SiteSetting.post_onebox_maxlength),
            }

            template = File.read("#{Rails.root}/lib/onebox/templates/discourse_topic_onebox.hbs")
            Mustache.render(template, args)
          end
        end

    end
  end
end
