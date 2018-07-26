require_relative 'multipart_boundary'

module HTTParty
  class Request
    class Body
      def initialize(params, query_string_normalizer: nil)
        @params = params
        @query_string_normalizer = query_string_normalizer
      end

      def call
        if params.respond_to?(:to_hash)
          multipart? ? generate_multipart : normalize_query(params)
        else
          params
        end
      end

      def boundary
        @boundary ||= MultipartBoundary.generate
      end

      def multipart?
        params.respond_to?(:to_hash) && has_file?(params.to_hash)
      end

      private

      def generate_multipart
        normalized_params = params.flat_map { |key, value| HashConversions.normalize_keys(key, value) }

        multipart = normalized_params.inject('') do |memo, (key, value)|
          memo += "--#{boundary}\r\n"
          memo += %(Content-Disposition: form-data; name="#{key}")
          # value.path is used to support ActionDispatch::Http::UploadedFile
          # https://github.com/jnunemaker/httparty/pull/585
          memo += %(; filename="#{File.basename(value.path)}") if file?(value)
          memo += "\r\n"
          if file?(value)
            # 1. check if 'ruby-mime-types' gem is 'required' in system
            if defined?(MimeMagic)
              puts 'MimeMagic is currently required'
              ctype = MimeMagic.by_magic(file).type
            elsif which("file")
              # 2. OR - try to use unix 'file' shell command
              # `file --mime -b "#{file.path}"`.chomp
              ctype = `file --mime -b "#{file.path}"`.chomp
            else
              ctype = "application/octet-stream"
            end
            memo += "Content-Type: #{ctype}\r\n"
          end
          memo += "\r\n"
          memo += file?(value) ? value.read : value.to_s
          memo += "\r\n"
        end

        multipart += "--#{boundary}--\r\n"
      end

      # from https://stackoverflow.com/a/5471032/2628223
      def which(cmd)
        exts = ENV['PATHEXT'] ? ENV['PATHEXT'].split(';') : ['']
        ENV['PATH'].split(File::PATH_SEPARATOR).each do |path|
          exts.each { |ext|
            exe = File.join(path, "#{cmd}#{ext}")
            return exe if File.executable?(exe) && !File.directory?(exe)
          }
        end
        return nil
      end

      def has_file?(hash)
        hash.detect do |key, value|
          if value.respond_to?(:to_hash) || includes_hash?(value)
            has_file?(value)
          elsif value.respond_to?(:to_ary)
            value.any? { |e| file?(e) }
          else
            file?(value)
          end
        end
      end

      def file?(object)
        object.respond_to?(:path) && object.respond_to?(:read) # add memoization
      end

      def includes_hash?(object)
        object.respond_to?(:to_ary) && object.any? { |e| e.respond_to?(:hash) }
      end

      def normalize_query(query)
        if query_string_normalizer
          query_string_normalizer.call(query)
        else
          HashConversions.to_params(query)
        end
      end

      attr_reader :params, :query_string_normalizer
    end
  end
end
