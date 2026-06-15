#include <stdio.h>
int main(void){
  const char* floors[]={"G","1","2","3"};
  printf("[elevator] native aarch64 controller online\n");
  for(int i=0;i<4;i++) printf("  -> floor %s\n", floors[i]);
  printf("[elevator] doors open. NATIVE, no emulation.\n");
  return 0;
}
