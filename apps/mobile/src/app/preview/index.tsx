import { router } from "expo-router";
import { TemplateGallery } from "../../preview/TemplateGallery";

export default function PreviewGalleryRoute() {
  return (
    <TemplateGallery
      onClose={() => {
        if (router.canGoBack()) router.back();
        else router.replace("/");
      }}
      onSelect={(template) =>
        router.push({
          pathname: "/preview/[templateId]",
          params: { templateId: template.id },
        })
      }
    />
  );
}
