import React from "react";
import { AlertCircle, RefreshCw } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";

export class ErrorBoundary extends React.Component {
  constructor(props) {
    super(props);
    this.state = { hasError: false, error: null };
  }

  static getDerivedStateFromError(error) {
    return { hasError: true, error };
  }

  componentDidCatch(error, errorInfo) {
    console.error("ErrorBoundary caught an error:", error, errorInfo);
  }

  handleReload = () => {
    window.location.reload();
  };

  render() {
    if (this.state.hasError) {
      return (
        <div className="flex min-h-svh items-center justify-center p-4 bg-background">
          <Card className="w-full max-w-md border-destructive/30 shadow-lg">
            <CardContent className="flex flex-col items-center p-6 text-center space-y-4">
              <div className="flex size-12 items-center justify-center rounded-full bg-destructive/10 text-destructive">
                <AlertCircle className="size-6" />
              </div>
              <div className="space-y-1">
                <h2 className="text-lg font-semibold text-foreground">
                  เกิดข้อผิดพลาดในการแสดงผล
                </h2>
                <p className="text-sm text-muted-foreground">
                  {this.state.error?.message || "โปรดลองโหลดหน้าเว็บใหม่อีกครั้ง"}
                </p>
              </div>
              <Button onClick={this.handleReload} className="gap-2">
                <RefreshCw className="size-4" />
                รีเฟรชหน้าเว็บ
              </Button>
            </CardContent>
          </Card>
        </div>
      );
    }

    return this.props.children;
  }
}
