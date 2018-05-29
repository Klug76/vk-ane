package com.marpies.utils
{
	import feathers.controls.Label;

    public class Logger
	{
		private static var log_: String = "";
		private static var view_: Label = null;

        public static function log( message: String ):void
		{
            trace(message);
			if (log_.length > 0)
				log_ += "\n";
			log_ += message;
			if (view_ !== null)
				view_.text = log_;
        }

		static public function addWindow(main: Main, nw: Number, nh: Number): void
		{
			if (view_ != null)
				return;
			view_ = new Label();
			view_.wordWrap = true;
			view_.text = log_;
			view_.width = nw;
			view_.height = nh;
			view_.includeInLayout = false;
			main.addChild(view_);
		}

		static public function getAllLogs(): String
		{
			return log_;
		}

    }

}
