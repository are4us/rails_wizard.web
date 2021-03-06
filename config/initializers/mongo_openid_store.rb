require 'openid/store/interface'

module OpenID
  module Store
    class Mongo < OpenID::Store::Interface
      class Association
        include MongoMapper::Document
        set_collection_name :open_id_authentication_associations

        key :issued,      Integer
        key :lifetime,    Integer
        key :handle,      String
        key :assoc_type,  String
        key :server_url,  String
        key :secret,      Binary

        def from_record
          OpenID::Association.new(handle, secret.to_s, issued, lifetime, assoc_type)
        end
      end

      class Nonce
        include MongoMapper::Document
        set_collection_name :open_id_authentication_nonces

        key :timestamp,   Integer
        key :server_url,  String
        key :salt,        String
      end
      
      def self.cleanup_nonces
        now = Time.now.to_i
        Nonce.delete_all(:timestamp => {'$gt' => now + OpenID::Nonce.skew})
        Nonce.delete_all(:timestamp => {'$lt' => now - OpenID::Nonce.skew})
      end

      def self.cleanup_associations
        now = Time.now.to_i
        Association.collection.remove("this.issued + this.lifetime > #{now}")
      end

      def store_association(server_url, assoc)
        remove_association(server_url, assoc.handle)
        Association.create(:server_url => server_url,
                           :handle     => assoc.handle,
                           :secret     => assoc.secret,
                           :issued     => assoc.issued,
                           :lifetime   => assoc.lifetime,
                           :assoc_type => assoc.assoc_type)
      end

      def get_association(server_url, handle = nil)
        assocs = if handle.blank?
            Association.find_all_by_server_url(server_url)
          else
            Association.find_all_by_server_url_and_handle(server_url, handle)
          end

        assocs.reverse.each do |assoc|
          a = assoc.from_record
          if a.expires_in == 0
            assoc.destroy
          else
            return a
          end
        end if assocs.any?

        return nil
      end

      def remove_association(server_url, handle)
        associations = Association.find_all_by_server_url_and_handle(server_url, handle)
        if associations.size > 0
          associations.each{|a| a.destroy}
          true
        else
          false
        end
      end

      def use_nonce(server_url, timestamp, salt)
        return false if Nonce.find_by_server_url_and_timestamp_and_salt(server_url, timestamp, salt)
        return false if (timestamp - Time.now.to_i).abs > OpenID::Nonce.skew
        Nonce.create(:server_url => server_url, :timestamp => timestamp, :salt => salt)
        return true
      end
    end
  end
end